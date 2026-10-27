// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 itsAllexB

// Shared by the SpringBoard tweak and the Settings pane.
// How each browser accepts an http(s) URL from another app.
//   DBStyleOpenURL:  <scheme>://open-url?url=<percent-encoded URL>
//   DBStyleReplace:  http -> <scheme>, https -> <secureScheme>, rest of the URL unchanged
//   DBStylePrefix:   <scheme>://<full URL>
// Sources (checked 2026-10-27):
//   Firefox  - firefox-ios Client/Application/NavigationRouter.swift ("open-url", query item "url")
//   Focus/Klar - focus-ios Blockzilla/NavigationPath.swift (host "open-url", query "url");
//                BLOCKZILLA_URL_SCHEME firefox-focus / firefox-klar, bundle ids org.mozilla.ios.Focus / .Klar
//   Brave    - brave-ios App/Configuration/Base.xcconfig BRAVE_URL_SCHEME = brave, Release MOZ_BUNDLE_ID
//              com.brave.ios.browser; NavigationRouterTests "brave://open-url?url=<escaped>"
//   Chrome   - chromium docs/ios/opening_links.md: googlechrome:// (http), googlechromes:// (https)
//   DuckDuckGo - duckduckgo/iOS Core/AppDeepLinkSchemes.swift quickLink "ddgQuickLink://<url>"
//   Edge, Opera - community-documented only (microsoft-edge-http(s)://, touch-http(s)://); listed only
//              when the installed app actually declares the scheme in its Info.plist.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DBStyle) { DBStyleOpenURL = 0, DBStyleReplace = 1, DBStylePrefix = 2 };

typedef struct {
    const char *bundleID;
    const char *name;
    const char *scheme;
    const char *secureScheme; // DBStyleReplace only
    DBStyle style;
} DBBrowser;

static const DBBrowser kDBBrowsers[] = {
    { "org.mozilla.ios.Firefox",   "Firefox",        "firefox",              NULL,                    DBStyleOpenURL },
    { "com.google.chrome.ios",     "Chrome",         "googlechrome",         "googlechromes",         DBStyleReplace },
    { "com.brave.ios.browser",     "Brave",          "brave",                NULL,                    DBStyleOpenURL },
    { "com.duckduckgo.mobile.ios", "DuckDuckGo",     "ddgQuickLink",         NULL,                    DBStylePrefix  },
    { "com.microsoft.msedge",      "Microsoft Edge", "microsoft-edge-http",  "microsoft-edge-https",  DBStyleReplace },
    { "org.mozilla.ios.Focus",     "Firefox Focus",  "firefox-focus",        NULL,                    DBStyleOpenURL },
    { "org.mozilla.ios.Klar",      "Firefox Klar",   "firefox-klar",         NULL,                    DBStyleOpenURL },
    { "com.opera.OperaTouch",      "Opera",          "touch-http",           "touch-https",           DBStyleReplace },
};
static const size_t kDBBrowserCount = sizeof(kDBBrowsers) / sizeof(kDBBrowsers[0]);

static inline const DBBrowser *DBBrowserForBundleID(NSString *bundleID) {
    if (![bundleID isKindOfClass:[NSString class]]) return NULL;
    for (size_t i = 0; i < kDBBrowserCount; i++)
        if ([bundleID isEqualToString:@(kDBBrowsers[i].bundleID)]) return &kDBBrowsers[i];
    return NULL;
}

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)applicationIsInstalled:(NSString *)bundleIdentifier;
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)bundleIdentifier;
- (BOOL)isPlaceholder;
- (NSArray *)publicURLSchemes;
- (NSArray *)privateURLSchemes;
- (BOOL)isInstalled;
@end

// Installed (not an offloaded placeholder) and really declares the scheme(s) we will use.
static inline BOOL DBBrowserUsable(const DBBrowser *b) {
    if (!b) return NO;
    Class ws = NSClassFromString(@"LSApplicationWorkspace");
    Class px = NSClassFromString(@"LSApplicationProxy");
    if (!ws || !px) return NO;
    NSString *bid = @(b->bundleID);
    if (![[ws defaultWorkspace] applicationIsInstalled:bid]) return NO;
    LSApplicationProxy *proxy = [px applicationProxyForIdentifier:bid];
    if (!proxy) return NO;
    if ([proxy respondsToSelector:@selector(isPlaceholder)] && [proxy isPlaceholder]) return NO;
    if ([proxy respondsToSelector:@selector(publicURLSchemes)]) {
        NSMutableSet *claimed = [NSMutableSet set];
        NSMutableArray *all = [NSMutableArray array];
        id pub = [proxy publicURLSchemes]; if ([pub isKindOfClass:[NSArray class]]) [all addObjectsFromArray:pub];
        if ([proxy respondsToSelector:@selector(privateURLSchemes)]) {
            id priv = [proxy privateURLSchemes]; if ([priv isKindOfClass:[NSArray class]]) [all addObjectsFromArray:priv];
        }
        for (id s in all) if ([s isKindOfClass:[NSString class]]) [claimed addObject:[s lowercaseString]];
        if (![claimed containsObject:[@(b->scheme) lowercaseString]]) return NO;
        if (b->secureScheme && ![claimed containsObject:[@(b->secureScheme) lowercaseString]]) return NO;
    }
    return YES;
}
