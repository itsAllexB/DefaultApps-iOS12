// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 itsAllexB

// DefaultAppsUI: the part of DefaultApps that runs inside apps (filter: UIKit).
//
// On iOS 12 tapping an email address or a mailto: link in a text view (Notes, Messages, ...) does
// not open Mail: DataDetectorsUI's DDSendMailAction reports interactionType 2 ("present a view
// controller") whenever an account is set up, and shows Apple's compose sheet inside the app, so
// SpringBoard never sees a request. When a mail app is chosen we report interactionType 0 instead;
// DDActionController then calls -performFromView:, which DDSendMailAction implements as
// -[DDAction _performFromView:byOpeningURL:] with its mailto: URL. That URL goes to SpringBoard,
// where the main tweak sends it to the chosen app. With "Default (Apple)" nothing changes.
//
// The choice comes from the notify state "com.itsallexb.defaultapps/state", published by the
// SpringBoard tweak (sandboxed apps cannot read its preferences file).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <notify.h>
#import "DAApps.h"

@interface DDAction : NSObject
- (NSURL *)url;
- (void)performFromView:(id)view;
@end

@interface DDSendMailAction : DDAction
@end

static int gToken = -1;

static const DAMailApp *DAActiveMailApp(void) {
    if (gToken < 0 && notify_register_check(kDAStateNotification, &gToken) != NOTIFY_STATUS_OK) {
        gToken = -1;
        return NULL;
    }
    uint64_t state = 0;
    if (notify_get_state(gToken, &state) != NOTIFY_STATUS_OK) return NULL;
    uint64_t idx = state & 0xff;
    if (idx == 0 || idx > kDAMailCount) return NULL;
    return &kDAMailApps[idx - 1];
}

%group DAMailSheet

%hook DDSendMailAction
- (int)interactionType {
    int type = %orig;
    if (type == 0) return type;
    @try {
        const DAMailApp *app = DAActiveMailApp();
        if (!app) return type;
        NSString *me = [[NSBundle mainBundle] bundleIdentifier];
        if ([me isEqualToString:@(app->bundleID)]) return type;
        NSURL *url = [self respondsToSelector:@selector(url)] ? [self url] : nil;
        if (![url isKindOfClass:[NSURL class]] || ![url.scheme.lowercaseString isEqualToString:@"mailto"]) return type;
        if (![self respondsToSelector:@selector(performFromView:)]) return type;
        return 0; // open the mailto: URL instead of showing the in-app sheet
    } @catch (NSException *e) {
        return type;
    }
}
%end

%end

static BOOL gHooked = NO;

static void DAHookIfReady(void) {
    if (gHooked) return;
    Class c = objc_getClass("DDSendMailAction");
    if (!c || ![c instancesRespondToSelector:@selector(interactionType)]) return;
    gHooked = YES;
    %init(DAMailSheet);
}

static void DAImageAdded(const struct mach_header *mh, intptr_t slide) {
    if (gHooked) return;
    Dl_info info;
    if (!dladdr(mh, &info) || !info.dli_fname || !strstr(info.dli_fname, "/DataDetectorsUI.framework/")) return;
    // Let the Objective-C runtime finish registering the image's classes first.
    dispatch_async(dispatch_get_main_queue(), ^{ DAHookIfReady(); });
}

%ctor {
    @autoreleasepool {
        if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) return;
        DAHookIfReady();
        if (!gHooked) _dyld_register_func_for_add_image(DAImageAdded);
    }
}
