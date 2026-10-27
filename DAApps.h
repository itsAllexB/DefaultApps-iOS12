// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 itsAllexB

// Supported apps. Shared by the SpringBoard tweak, the in-app helper and the Settings pane.
// An app is offered only when it is installed (not an offloaded placeholder) and its Info.plist
// really declares the URL scheme we send it, so a wrong or changed bundle id simply hides the row.
//
// Sources (checked 2026-10-27):
//   Browsers - see DefaultBrowser 2.0 (firefox-ios NavigationRouter, focus-ios NavigationPath,
//              brave-ios Base.xcconfig, chromium docs/ios/opening_links.md, duckduckgo AppDeepLinkSchemes);
//              Edge and Opera are community-documented only.
//   Mail     - firefox-ios Client/Frontend/Browser/MailProviders.swift (v36.0, the iOS 12 era release,
//              and current main for ProtonMail) and MailProvidersTests.swift.
//   Maps     - Google: developers.google.com/maps/documentation/urls/ios-urlscheme
//              Waze: developers.google.com/waze/deeplinks
//              Citymapper: citymapper.com "Launch Citymapper for Directions"
//              Yandex: yandex.com/dev/yandex-apps-launch-maps (ll/pt are lng,lat; rtext is lat,lng)
//              Organic Maps / MAPS.ME: organicmaps libs/map/mwm_url.cpp and its tests
//   Bundle ids - App Store lookup API (itunes.apple.com/lookup?bundleId=...).

#import <Foundation/Foundation.h>
#import "DAURL.h"

#define kDADomain              "com.itsallexb.defaultapps"
#define kDANotification        "com.itsallexb.defaultapps/prefschanged"
#define kDAStateNotification   "com.itsallexb.defaultapps/state"
#define kDAOldDomain           "com.itsallexb.defaultbrowser"
#define kDAApple               @"apple"
#define kDAMigrationMarker     @"/var/mobile/Library/DefaultApps/from-defaultbrowser"

typedef struct {
    const char *bundleID;
    const char *name;
    const char *scheme;
    const char *secureScheme;
    DABrowserStyle style;
} DABrowser;

typedef struct {
    const char *bundleID;
    const char *name;
    const char *scheme;
    DAMailKind kind;
} DAMailApp;

typedef struct {
    const char *bundleID;
    const char *name;
    const char *scheme;
    DAMapsKind kind;
} DAMapsApp;

static const DABrowser kDABrowsers[] = {
    { "org.mozilla.ios.Firefox",   "Firefox",        "firefox",             NULL,                   DABrowserStyleOpenURL },
    { "com.google.chrome.ios",     "Chrome",         "googlechrome",        "googlechromes",        DABrowserStyleReplace },
    { "com.brave.ios.browser",     "Brave",          "brave",               NULL,                   DABrowserStyleOpenURL },
    { "com.duckduckgo.mobile.ios", "DuckDuckGo",     "ddgQuickLink",        NULL,                   DABrowserStylePrefix  },
    { "com.microsoft.msedge",      "Microsoft Edge", "microsoft-edge-http", "microsoft-edge-https", DABrowserStyleReplace },
    { "org.mozilla.ios.Focus",     "Firefox Focus",  "firefox-focus",       NULL,                   DABrowserStyleOpenURL },
    { "org.mozilla.ios.Klar",      "Firefox Klar",   "firefox-klar",        NULL,                   DABrowserStyleOpenURL },
    { "com.opera.OperaTouch",      "Opera",          "touch-http",          "touch-https",          DABrowserStyleReplace },
};
static const size_t kDABrowserCount = sizeof(kDABrowsers) / sizeof(kDABrowsers[0]);

static const DAMailApp kDAMailApps[] = {
    { "com.google.Gmail",             "Gmail",      "googlegmail",   DAMailGmail    },
    { "com.microsoft.Office.Outlook", "Outlook",    "ms-outlook",    DAMailOutlook  },
    { "com.readdle.smartemail",       "Spark",      "readdle-spark", DAMailSpark    },
    { "com.yahoo.Aerogram",           "Yahoo Mail", "ymail",         DAMailYahoo    },
    { "ch.protonmail.protonmail",     "Proton Mail","protonmail",    DAMailProton   },
    { "it.bloop.airmail2",            "Airmail",    "airmail",       DAMailAirmail  },
    { "com.fastmail.FastMail",        "Fastmail",   "fastmail",      DAMailFastmail },
    { "com.my.mail",                  "myMail",     "mymail-mailto", DAMailMyMail   },
};
static const size_t kDAMailCount = sizeof(kDAMailApps) / sizeof(kDAMailApps[0]);

static const DAMapsApp kDAMapsApps[] = {
    { "com.google.Maps",     "Google Maps",  "comgooglemaps", DAMapsGoogle     },
    { "com.waze.iphone",     "Waze",         "waze",          DAMapsWaze       },
    { "azdev.citymapper",    "Citymapper",   "citymapper",    DAMapsCitymapper },
    { "ru.yandex.traffic",   "Yandex Maps",  "yandexmaps",    DAMapsYandex     },
    { "app.organicmaps",     "Organic Maps", "om",            DAMapsOrganic    },
    { "com.mapswithme.full", "MAPS.ME",      "mapsme",        DAMapsMapsMe     },
};
static const size_t kDAMapsCount = sizeof(kDAMapsApps) / sizeof(kDAMapsApps[0]);

static inline const DABrowser *DABrowserForID(NSString *bid) {
    if (![bid isKindOfClass:[NSString class]]) return NULL;
    for (size_t i = 0; i < kDABrowserCount; i++) if ([bid isEqualToString:@(kDABrowsers[i].bundleID)]) return &kDABrowsers[i];
    return NULL;
}
static inline const DAMailApp *DAMailForID(NSString *bid) {
    if (![bid isKindOfClass:[NSString class]]) return NULL;
    for (size_t i = 0; i < kDAMailCount; i++) if ([bid isEqualToString:@(kDAMailApps[i].bundleID)]) return &kDAMailApps[i];
    return NULL;
}
static inline const DAMapsApp *DAMapsForID(NSString *bid) {
    if (![bid isKindOfClass:[NSString class]]) return NULL;
    for (size_t i = 0; i < kDAMapsCount; i++) if ([bid isEqualToString:@(kDAMapsApps[i].bundleID)]) return &kDAMapsApps[i];
    return NULL;
}

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)applicationIsInstalled:(NSString *)bundleIdentifier;
- (NSArray *)applicationsAvailableForHandlingURLScheme:(NSString *)scheme; // iOS 12
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)bundleIdentifier;
- (NSString *)bundleIdentifier;
- (BOOL)isPlaceholder;
- (NSArray *)publicURLSchemes;  // newer iOS only
- (NSArray *)privateURLSchemes; // newer iOS only
- (id)objectForInfoDictionaryKey:(NSString *)key ofClass:(Class)cls;
@end

// Does the installed app declare this URL scheme? iOS 12's LSApplicationProxy has no
// publicURLSchemes, so ask LaunchServices which apps handle the scheme, and fall back to the
// app's own CFBundleURLTypes.
static inline BOOL DAAppClaimsScheme(LSApplicationProxy *proxy, NSString *bid, NSString *scheme) {
    NSString *want = scheme.lowercaseString;
    if ([proxy respondsToSelector:@selector(publicURLSchemes)]) {
        NSMutableArray *all = [NSMutableArray array];
        id pub = [proxy publicURLSchemes];
        if ([pub isKindOfClass:[NSArray class]]) [all addObjectsFromArray:pub];
        if ([proxy respondsToSelector:@selector(privateURLSchemes)]) {
            id priv = [proxy privateURLSchemes];
            if ([priv isKindOfClass:[NSArray class]]) [all addObjectsFromArray:priv];
        }
        for (id s in all) if ([s isKindOfClass:[NSString class]] && [[s lowercaseString] isEqualToString:want]) return YES;
        return NO;
    }
    id ws = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
    if ([ws respondsToSelector:@selector(applicationsAvailableForHandlingURLScheme:)]) {
        id apps = [ws applicationsAvailableForHandlingURLScheme:scheme];
        if ([apps isKindOfClass:[NSArray class]])
            for (id a in apps)
                if ([a respondsToSelector:@selector(bundleIdentifier)] && [[a bundleIdentifier] isEqualToString:bid]) return YES;
    }
    if ([proxy respondsToSelector:@selector(objectForInfoDictionaryKey:ofClass:)]) {
        id types = [proxy objectForInfoDictionaryKey:@"CFBundleURLTypes" ofClass:[NSArray class]];
        if ([types isKindOfClass:[NSArray class]])
            for (id t in types) {
                id schemes = [t isKindOfClass:[NSDictionary class]] ? t[@"CFBundleURLSchemes"] : nil;
                if (![schemes isKindOfClass:[NSArray class]]) continue;
                for (id s in schemes) if ([s isKindOfClass:[NSString class]] && [[s lowercaseString] isEqualToString:want]) return YES;
            }
    }
    return NO;
}

// Installed (not an offloaded placeholder) and declares every scheme passed in.
static inline BOOL DAAppUsable(const char *bundleID, const char *scheme, const char *secureScheme) {
    if (!bundleID || !scheme) return NO;
    Class ws = NSClassFromString(@"LSApplicationWorkspace");
    Class px = NSClassFromString(@"LSApplicationProxy");
    if (!ws || !px) return NO;
    NSString *bid = @(bundleID);
    if (![[ws defaultWorkspace] applicationIsInstalled:bid]) return NO;
    LSApplicationProxy *proxy = [px applicationProxyForIdentifier:bid];
    if (!proxy) return NO;
    if ([proxy respondsToSelector:@selector(isPlaceholder)] && [proxy isPlaceholder]) return NO;
    if (!DAAppClaimsScheme(proxy, bid, @(scheme))) return NO;
    if (secureScheme && !DAAppClaimsScheme(proxy, bid, @(secureScheme))) return NO;
    return YES;
}

static inline BOOL DABrowserUsable(const DABrowser *b) { return b && DAAppUsable(b->bundleID, b->scheme, b->secureScheme); }
static inline BOOL DAMailUsable(const DAMailApp *a)    { return a && DAAppUsable(a->bundleID, a->scheme, NULL); }
static inline BOOL DAMapsUsable(const DAMapsApp *a)    { return a && DAAppUsable(a->bundleID, a->scheme, NULL); }
