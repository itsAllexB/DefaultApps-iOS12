// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 itsAllexB

// URL translation for DefaultApps. Pure Foundation, no private API, so it also builds on the Mac
// for the unit tests in tests/.

#import <Foundation/Foundation.h>

// ---- Browsers -------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, DABrowserStyle) {
    DABrowserStyleOpenURL = 0, // <scheme>://open-url?url=<percent-encoded URL>
    DABrowserStyleReplace = 1, // http -> <scheme>, https -> <secureScheme>, rest unchanged
    DABrowserStylePrefix  = 2, // <scheme>://<full URL>
};

// ---- Mail apps ------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, DAMailKind) {
    DAMailGmail = 0,
    DAMailOutlook,
    DAMailSpark,
    DAMailYahoo,
    DAMailProton,
    DAMailAirmail,
    DAMailFastmail,
    DAMailMyMail,
};

// ---- Maps apps ------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, DAMapsKind) {
    DAMapsGoogle = 0,
    DAMapsWaze,
    DAMapsCitymapper,
    DAMapsYandex,
    DAMapsOrganic,
    DAMapsMapsMe,
};

#ifdef __cplusplus
extern "C" {
#endif

// Browser: rewrite an http(s) URL for the browser's scheme. nil if not possible.
NSURL *DABrowserURL(DABrowserStyle style, NSString *scheme, NSString *secureScheme, NSURL *url);

// Mail: parse a mailto: URL (RFC 6068). Returns nil if it is not a mailto: URL.
// Keys: "to", "cc", "bcc" (comma separated, no spaces), "subject", "body". Absent keys are absent.
NSDictionary<NSString *, NSString *> *DAParseMailto(NSURL *url);
// Build the compose URL for a mail app. nil if a field cannot be carried (for example bcc in
// Yahoo Mail) so the caller can leave the link to Apple Mail instead of dropping a recipient.
NSURL *DAMailComposeURL(DAMailKind kind, NSDictionary<NSString *, NSString *> *fields);

// Maps: is this an Apple Maps link (maps:, map:, http(s)://maps.apple.com)?
BOOL DAIsAppleMapsURL(NSURL *url);
// Parse an Apple Maps link into a normalised dictionary. nil if not an Apple Maps link.
// Keys (all optional): "q" (search text), "label" (name of a pinned place), "pin" (lat,lng of a
// pinned place), "center" (lat,lng), "z" (zoom), "t" (m/k/h/r), "saddr", "daddr", "mode"
// (driving/walking/transit/cycling), "directions" ("1" when it is a directions request).
NSDictionary<NSString *, NSString *> *DAParseAppleMaps(NSURL *url);
// Build the URL for a maps app. nil if the link cannot be expressed for that app.
NSURL *DAMapsURL(DAMapsKind kind, NSDictionary<NSString *, NSString *> *m);

// Helpers (exposed for tests).
NSString *DAEncode(NSString *s, NSString *extraAllowed);
BOOL DAParseCoordinate(NSString *s, double *lat, double *lng);

#ifdef __cplusplus
}
#endif
