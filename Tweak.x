// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 itsAllexB

// DefaultApps 3.1.0
// Pick the default browser, mail app and maps app on iOS 12, like iOS 14's default apps.
//
// Hook point (SpringBoard, iOS 12):
//   -[SBMainWorkspace systemService:handleOpenApplicationRequest:withCompletion:]
// Every "open this URL" from an app (UIApplication openURL:, links, data detector actions,
// LSApplicationWorkspace openURL:...) is resolved by LaunchServices in the calling process and
// reaches SpringBoard here as an FBSystemServiceOpenApplicationRequest: bundleIdentifier is the app
// LaunchServices picked and options["__PayloadURL"] is the URL. We change both before %orig runs:
//   - http/https aimed at Safari               -> chosen browser
//   - mailto: aimed at Mail (com.apple.mobilemail) -> chosen mail app's compose URL
//   - maps:/map:/maps.apple.com aimed at Maps (or at Safari, when Maps is deleted) -> chosen maps app
// Mail links that never leave the app (the in-app "New Message" sheet of data detectors) are
// handled by DefaultAppsUI (UITweak.x), which turns them into a normal mailto: open first.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <notify.h>
#import "DAApps.h"

#define kDADomainCF CFSTR(kDADomain)

static NSString *const kDASafari = @"com.apple.mobilesafari";
static NSString *const kDASafariViewService = @"com.apple.SafariViewService";
static NSString *const kDAMail = @"com.apple.mobilemail";
static NSString *const kDAMaps = @"com.apple.Maps";

static BOOL gEnabled = YES;
static BOOL gDebug = NO;
static NSString *gBrowser = @"apple";
static NSString *gMail = @"apple";
static NSString *gMaps = @"apple";
static int gStateToken = -1;

@interface FBSOpenApplicationOptions : NSObject
+ (id)optionsWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionary;
@end

@interface FBProcess : NSObject
- (NSString *)bundleIdentifier;
@end

@interface FBSystemServiceOpenApplicationRequest : NSObject
- (NSString *)bundleIdentifier;
- (void)setBundleIdentifier:(NSString *)bundleIdentifier;
- (FBProcess *)clientProcess;
- (FBSOpenApplicationOptions *)options;
- (void)setOptions:(FBSOpenApplicationOptions *)options;
@end

// ---- Preferences -----------------------------------------------------------------------------

static id DACopy(CFStringRef key, CFStringRef domain) {
    CFPropertyListRef v = CFPreferencesCopyAppValue(key, domain);
    return v ? (__bridge_transfer id)v : nil;
}

static NSString *DAString(id v) { return [v isKindOfClass:[NSString class]] ? v : nil; }

static void DAUpdateState(void) {
    // Read by DefaultAppsUI inside apps (sandboxed apps cannot read our plist, but can read a
    // notify state): bits 0-7 = 1 + index of the active mail app, 0 when mail stays with Apple Mail.
    uint64_t state = 0;
    if (gEnabled) {
        const DAMailApp *mail = DAMailForID(gMail);
        if (mail && DAMailUsable(mail)) state |= (uint64_t)(mail - kDAMailApps + 1);
        const DAMapsApp *maps = DAMapsForID(gMaps);
        if (maps && DAMapsUsable(maps)) state |= (uint64_t)(maps - kDAMapsApps + 1) << 8;
    }
    if (gStateToken < 0 && notify_register_check(kDAStateNotification, &gStateToken) != NOTIFY_STATUS_OK) {
        gStateToken = -1;
        return;
    }
    uint64_t old = 0;
    notify_get_state(gStateToken, &old);
    if (old != state) {
        notify_set_state(gStateToken, state);
        notify_post(kDAStateNotification);
    }
}

static void DALoadPrefs(void) {
    CFPreferencesAppSynchronize(kDADomainCF);
    id en = DACopy(CFSTR("enabled"), kDADomainCF);
    gEnabled = [en respondsToSelector:@selector(boolValue)] ? [en boolValue] : YES;
    id dbg = DACopy(CFSTR("debug"), kDADomainCF);
    gDebug = [dbg respondsToSelector:@selector(boolValue)] ? [dbg boolValue] : NO;
    NSString *b = DAString(DACopy(CFSTR("browser"), kDADomainCF));
    NSString *m = DAString(DACopy(CFSTR("mail"), kDADomainCF));
    NSString *p = DAString(DACopy(CFSTR("maps"), kDADomainCF));
    gBrowser = DABrowserForID(b) ? [b copy] : kDAApple;
    gMail = DAMailForID(m) ? [m copy] : kDAApple;
    gMaps = DAMapsForID(p) ? [p copy] : kDAApple;
    DAUpdateState();
}

// ---- Redirect --------------------------------------------------------------------------------

static NSString *DAPayloadURLKey(void) {
    static NSString *key = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *__unsafe_unretained *sym =
            (NSString *__unsafe_unretained *)dlsym(RTLD_DEFAULT, "FBSOpenApplicationOptionKeyPayloadURL");
        key = (sym && *sym) ? [*sym copy] : @"__PayloadURL";
    });
    return key;
}

static BOOL DAIsBrowserClient(NSString *client) {
    if (![client isKindOfClass:[NSString class]]) return NO;
    if ([client hasPrefix:kDASafari] || [client isEqualToString:kDASafariViewService]) return YES;
    // Any known browser (and its extensions) asking for Safari did so on purpose ("Open in Safari").
    for (size_t i = 0; i < kDABrowserCount; i++)
        if ([client hasPrefix:@(kDABrowsers[i].bundleID)]) return YES;
    return NO;
}

// Works out the new target for a request. Returns nil to leave it alone.
static NSURL *DARewrite(NSString *target, NSString *client, NSURL *url, NSString **newTarget) {
    NSString *scheme = url.scheme.lowercaseString;

    // Mail: mailto: that LaunchServices gave to Apple Mail.
    if ([scheme isEqualToString:@"mailto"]) {
        if (![target isEqualToString:kDAMail] || [gMail isEqualToString:kDAApple]) return nil;
        const DAMailApp *app = DAMailForID(gMail);
        if (!app || [client hasPrefix:@(app->bundleID)] || [client hasPrefix:kDAMail]) return nil;
        if (!DAMailUsable(app)) return nil;
        NSURL *u = DAMailComposeURL(app->kind, DAParseMailto(url));
        if (u) *newTarget = @(app->bundleID);
        return u;
    }

    // Maps: Apple Maps links that go to Apple Maps (or to Safari when Apple Maps is deleted).
    if (DAIsAppleMapsURL(url) && ([target isEqualToString:kDAMaps] || [target isEqualToString:kDASafari])
        && ![gMaps isEqualToString:kDAApple]) {
        const DAMapsApp *app = DAMapsForID(gMaps);
        if (app && ![client hasPrefix:@(app->bundleID)] && ![client hasPrefix:kDAMaps] && DAMapsUsable(app)) {
            NSURL *u = DAMapsURL(app->kind, DAParseAppleMaps(url));
            if (u) { *newTarget = @(app->bundleID); return u; }
        }
        // Not translatable: fall through, so a maps.apple.com link aimed at Safari still follows the browser choice.
    }

    // Browser: http/https aimed at Safari.
    if (([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) && [target isEqualToString:kDASafari]
        && ![gBrowser isEqualToString:kDAApple] && !DAIsBrowserClient(client)) {
        const DABrowser *b = DABrowserForID(gBrowser);
        if (!DABrowserUsable(b)) return nil; // not installed / offloaded / scheme missing: keep Safari
        NSURL *u = DABrowserURL(b->style, @(b->scheme), b->secureScheme ? @(b->secureScheme) : nil, url);
        if (u) *newTarget = @(b->bundleID);
        return u;
    }
    return nil;
}

static void DAMaybeRedirect(FBSystemServiceOpenApplicationRequest *request) {
    FBSOpenApplicationOptions *originalOptions = nil;
    NSString *originalTarget = nil;
    BOOL mutated = NO;
    @try {
        if (!request
            || ![request respondsToSelector:@selector(bundleIdentifier)]
            || ![request respondsToSelector:@selector(setBundleIdentifier:)]
            || ![request respondsToSelector:@selector(options)]
            || ![request respondsToSelector:@selector(setOptions:)]) return;

        NSString *target = [request bundleIdentifier];
        if (![target isKindOfClass:[NSString class]]) return;

        NSString *client = nil;
        if ([request respondsToSelector:@selector(clientProcess)]) {
            FBProcess *p = [request clientProcess];
            if (p && [p respondsToSelector:@selector(bundleIdentifier)]) client = [p bundleIdentifier];
        }
        if (![client isKindOfClass:[NSString class]]) client = @"";

        FBSOpenApplicationOptions *options = [request options];
        if (!options || ![options respondsToSelector:@selector(dictionary)]) return;
        NSDictionary *dict = [options dictionary];
        if (![dict isKindOfClass:[NSDictionary class]]) return;
        NSString *key = DAPayloadURLKey();
        NSURL *url = dict[key];
        if (![url isKindOfClass:[NSURL class]]) return;

        if (gDebug) NSLog(@"[DefaultApps] open request client=%@ target=%@ url=%@", client, target, url);
        if (!gEnabled) return;

        NSString *newTarget = nil;
        NSURL *newURL = DARewrite(target, client, url, &newTarget);
        if (!newURL || !newTarget) return;

        Class optionsClass = objc_getClass("FBSOpenApplicationOptions");
        if (!optionsClass || ![optionsClass respondsToSelector:@selector(optionsWithDictionary:)]) return;
        NSMutableDictionary *newDict = [dict mutableCopy];
        newDict[key] = newURL;
        id newOptions = [optionsClass optionsWithDictionary:newDict];
        if (!newOptions) return;

        originalOptions = options;
        originalTarget = target;
        mutated = YES;
        [request setOptions:newOptions];
        [request setBundleIdentifier:newTarget];
        NSLog(@"[DefaultApps] %@ link from %@ for %@ -> %@", url.scheme, client, target, newTarget);
        if (gDebug) NSLog(@"[DefaultApps] rewritten url=%@", newURL);
    } @catch (NSException *e) {
        NSLog(@"[DefaultApps] exception, leaving request unchanged: %@", e);
        if (mutated) {
            @try {
                [request setOptions:originalOptions];
                [request setBundleIdentifier:originalTarget];
            } @catch (NSException *e2) {}
        }
    }
}

%group DAHooks

%hook SBMainWorkspace
- (void)systemService:(id)service handleOpenApplicationRequest:(id)request withCompletion:(id)completion {
    DAMaybeRedirect(request);
    %orig;
}
%end

%end

static void DAPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DALoadPrefs();
}

static void DAAppsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ DAUpdateState(); });
}

%ctor {
    @autoreleasepool {
        Class cls = objc_getClass("SBMainWorkspace");
        SEL sel = @selector(systemService:handleOpenApplicationRequest:withCompletion:);
        if (!cls || ![cls instancesRespondToSelector:sel]) {
            NSLog(@"[DefaultApps] SBMainWorkspace handler not found; not hooking");
            return;
        }
        DALoadPrefs();
        %init(DAHooks);
        CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(darwin, NULL, DAPrefsChanged, CFSTR(kDANotification), NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(darwin, NULL, DAAppsChanged, CFSTR("com.apple.mobile.application_installed"), NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(darwin, NULL, DAAppsChanged, CFSTR("com.apple.mobile.application_uninstalled"), NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
