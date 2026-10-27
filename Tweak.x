// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 itsAllexB

// DefaultBrowser 2.0.0 (successor of FirefoxDefault 1.0.0)
// Sends http/https links that other apps hand to Safari to the browser picked in Settings.
//
// Hook point (SpringBoard, iOS 12), unchanged from FirefoxDefault:
//   -[SBMainWorkspace systemService:handleOpenApplicationRequest:withCompletion:]
// Every "open this URL" from an app (UIApplication openURL:, links, data detectors, ...) is
// resolved by LaunchServices in the calling process and arrives here as an
// FBSystemServiceOpenApplicationRequest (bundleIdentifier + options["__PayloadURL"]).
// Universal links were already resolved to their own app, so only requests aimed at Safari change.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "DBBrowsers.h"

#define kDBDomain CFSTR("com.itsallexb.defaultbrowser")
#define kDBNotification "com.itsallexb.defaultbrowser/prefschanged"

static NSString *const kDBSafariBundleID = @"com.apple.mobilesafari";
static NSString *const kDBSafariViewServiceBundleID = @"com.apple.SafariViewService";

static BOOL gEnabled = YES;
static NSString *gBrowserID = @"org.mozilla.ios.Firefox";

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

static void DBLoadPrefs(void) {
    CFPreferencesAppSynchronize(kDBDomain);
    CFPropertyListRef en = CFPreferencesCopyAppValue(CFSTR("enabled"), kDBDomain);
    CFPropertyListRef br = CFPreferencesCopyAppValue(CFSTR("browser"), kDBDomain);
    gEnabled = en ? [(__bridge id)en boolValue] : YES;
    NSString *bid = br ? [(__bridge id)br copy] : nil;
    gBrowserID = ([bid isKindOfClass:[NSString class]] && DBBrowserForBundleID(bid)) ? bid : @"org.mozilla.ios.Firefox";
    if (en) CFRelease(en);
    if (br) CFRelease(br);
}

static NSString *DBPayloadURLKey(void) {
    static NSString *key = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *__unsafe_unretained *sym =
            (NSString *__unsafe_unretained *)dlsym(RTLD_DEFAULT, "FBSOpenApplicationOptionKeyPayloadURL");
        key = (sym && *sym) ? [*sym copy] : @"__PayloadURL";
    });
    return key;
}

static NSString *DBPercentEncode(NSString *string) {
    static NSCharacterSet *unreserved = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // RFC 3986 unreserved characters only (explicit ASCII).
        unreserved = [NSCharacterSet characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    });
    return [string stringByAddingPercentEncodingWithAllowedCharacters:unreserved];
}

static NSURL *DBBrowserURL(const DBBrowser *b, NSURL *url) {
    NSString *absolute = url.absoluteString;
    if (absolute.length == 0) return nil;
    NSString *scheme = url.scheme.lowercaseString;
    switch (b->style) {
        case DBStyleOpenURL: {
            NSString *enc = DBPercentEncode(absolute);
            if (enc.length == 0) return nil;
            return [NSURL URLWithString:[NSString stringWithFormat:@"%s://open-url?url=%@", b->scheme, enc]];
        }
        case DBStyleReplace: {
            NSRange r = [absolute rangeOfString:@":"];
            if (r.location == NSNotFound) return nil;
            const char *newScheme = [scheme isEqualToString:@"https"] ? b->secureScheme : b->scheme;
            return [NSURL URLWithString:[@(newScheme) stringByAppendingString:[absolute substringFromIndex:r.location]]];
        }
        case DBStylePrefix:
            return [NSURL URLWithString:[NSString stringWithFormat:@"%s://%@", b->scheme, absolute]];
    }
    return nil;
}

static BOOL DBIsExcludedClient(NSString *client) {
    if (![client isKindOfClass:[NSString class]]) return NO;
    if ([client hasPrefix:kDBSafariBundleID] || [client isEqualToString:kDBSafariViewServiceBundleID]) return YES;
    // Any known browser (and its extensions) asking for Safari did so on purpose ("Open in Safari").
    for (size_t i = 0; i < kDBBrowserCount; i++)
        if ([client hasPrefix:@(kDBBrowsers[i].bundleID)]) return YES;
    return NO;
}

static void DBMaybeRedirect(FBSystemServiceOpenApplicationRequest *request) {
    if (!gEnabled) return;
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
        if (![target isKindOfClass:[NSString class]] || ![target isEqualToString:kDBSafariBundleID]) return;

        if ([request respondsToSelector:@selector(clientProcess)]) {
            FBProcess *client = [request clientProcess];
            if (client && [client respondsToSelector:@selector(bundleIdentifier)]
                && DBIsExcludedClient([client bundleIdentifier])) return;
        }

        FBSOpenApplicationOptions *options = [request options];
        if (!options || ![options respondsToSelector:@selector(dictionary)]) return;
        NSDictionary *dict = [options dictionary];
        if (![dict isKindOfClass:[NSDictionary class]]) return;

        NSString *key = DBPayloadURLKey();
        NSURL *url = dict[key];
        if (![url isKindOfClass:[NSURL class]]) return;
        NSString *scheme = url.scheme.lowercaseString;
        if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return;

        const DBBrowser *browser = DBBrowserForBundleID(gBrowserID);
        if (!DBBrowserUsable(browser)) return; // not installed / offloaded / scheme missing: keep Safari

        NSURL *newURL = DBBrowserURL(browser, url);
        if (!newURL) return;

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
        [request setBundleIdentifier:@(browser->bundleID)];
    } @catch (NSException *e) {
        NSLog(@"[DefaultBrowser] exception, leaving request unchanged: %@", e);
        if (mutated) {
            @try {
                [request setOptions:originalOptions];
                [request setBundleIdentifier:originalTarget];
            } @catch (NSException *e2) {}
        }
    }
}

%group DBHooks

%hook SBMainWorkspace
- (void)systemService:(id)service handleOpenApplicationRequest:(id)request withCompletion:(id)completion {
    DBMaybeRedirect(request);
    %orig;
}
%end

%end

static void DBPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DBLoadPrefs();
}

%ctor {
    @autoreleasepool {
        Class cls = objc_getClass("SBMainWorkspace");
        SEL sel = @selector(systemService:handleOpenApplicationRequest:withCompletion:);
        if (!cls || ![cls instancesRespondToSelector:sel]) {
            NSLog(@"[DefaultBrowser] SBMainWorkspace handler not found; not hooking");
            return;
        }
        DBLoadPrefs();
        %init(DBHooks);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DBPrefsChanged,
            CFSTR(kDBNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
