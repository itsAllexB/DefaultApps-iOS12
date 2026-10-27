// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 itsAllexB

#import "DAURL.h"

// ============================================================================================
// Encoding helpers
// ============================================================================================

// RFC 3986 "unreserved" characters only, written out so the set does not depend on the locale
// or on what Foundation's URL*Allowed sets happen to contain on a given iOS version.
static NSString *const kDAUnreserved = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";

NSString *DAEncode(NSString *s, NSString *extraAllowed) {
    if (![s isKindOfClass:[NSString class]]) return nil;
    NSCharacterSet *set = [NSCharacterSet characterSetWithCharactersInString:
        extraAllowed.length ? [kDAUnreserved stringByAppendingString:extraAllowed] : kDAUnreserved];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:set];
}

// Percent-decode; a malformed escape leaves the text as it was rather than dropping it.
static NSString *DADecode(NSString *s, BOOL plusIsSpace) {
    if (!s) return nil;
    if (plusIsSpace) s = [s stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    NSString *d = [s stringByRemovingPercentEncoding];
    return d ?: s;
}

static NSString *DATrim(NSString *s) {
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// Builds base + "?" + name=value&... (values already encoded), skipping empty values.
static NSURL *DAJoin(NSString *base, NSArray<NSArray<NSString *> *> *pairs) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSArray<NSString *> *p in pairs)
        if (p.count == 2 && p[1].length) [parts addObject:[NSString stringWithFormat:@"%@=%@", p[0], p[1]]];
    NSString *s = parts.count ? [NSString stringWithFormat:@"%@?%@", base, [parts componentsJoinedByString:@"&"]] : base;
    return [NSURL URLWithString:s];
}

// ============================================================================================
// Browsers
// ============================================================================================

NSURL *DABrowserURL(DABrowserStyle style, NSString *scheme, NSString *secureScheme, NSURL *url) {
    NSString *absolute = url.absoluteString;
    if (absolute.length == 0 || scheme.length == 0) return nil;
    NSString *urlScheme = url.scheme.lowercaseString;
    if (!([urlScheme isEqualToString:@"http"] || [urlScheme isEqualToString:@"https"])) return nil;
    switch (style) {
        case DABrowserStyleOpenURL: {
            NSString *enc = DAEncode(absolute, nil);
            return enc.length ? [NSURL URLWithString:[NSString stringWithFormat:@"%@://open-url?url=%@", scheme, enc]] : nil;
        }
        case DABrowserStyleReplace: {
            NSRange r = [absolute rangeOfString:@":"];
            if (r.location == NSNotFound) return nil;
            NSString *newScheme = ([urlScheme isEqualToString:@"https"] && secureScheme.length) ? secureScheme : scheme;
            return [NSURL URLWithString:[newScheme stringByAppendingString:[absolute substringFromIndex:r.location]]];
        }
        case DABrowserStylePrefix:
            return [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", scheme, absolute]];
    }
    return nil;
}

// ============================================================================================
// Mail
// ============================================================================================

static void DAAddAddresses(NSMutableArray *list, NSString *decoded) {
    for (NSString *part in [decoded componentsSeparatedByString:@","]) {
        NSString *a = DATrim(part);
        if (a.length) [list addObject:a];
    }
}

NSDictionary<NSString *, NSString *> *DAParseMailto(NSURL *url) {
    if (![url isKindOfClass:[NSURL class]] || ![url.scheme.lowercaseString isEqualToString:@"mailto"]) return nil;
    NSString *abs = url.absoluteString;
    NSRange colon = [abs rangeOfString:@":"];
    if (colon.location == NSNotFound) return nil;
    NSString *rest = [abs substringFromIndex:NSMaxRange(colon)];
    NSRange hash = [rest rangeOfString:@"#"];
    if (hash.location != NSNotFound) rest = [rest substringToIndex:hash.location];
    if ([rest hasPrefix:@"//"]) rest = [rest substringFromIndex:2]; // tolerate "mailto://x@y"

    NSString *addrPart = rest, *query = nil;
    NSRange q = [rest rangeOfString:@"?"];
    if (q.location != NSNotFound) {
        addrPart = [rest substringToIndex:q.location];
        query = [rest substringFromIndex:NSMaxRange(q)];
    }

    NSMutableArray *to = [NSMutableArray array], *cc = [NSMutableArray array], *bcc = [NSMutableArray array];
    NSString *subject = nil, *body = nil;
    // RFC 6068: "+" is a literal plus in mailto, never a space.
    DAAddAddresses(to, DADecode(addrPart, NO));
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        if (!pair.length) continue;
        NSRange eq = [pair rangeOfString:@"="];
        NSString *name = eq.location == NSNotFound ? pair : [pair substringToIndex:eq.location];
        NSString *value = eq.location == NSNotFound ? @"" : [pair substringFromIndex:NSMaxRange(eq)];
        name = DADecode(name, NO).lowercaseString;
        value = DADecode(value, NO);
        if ([name isEqualToString:@"to"]) DAAddAddresses(to, value);
        else if ([name isEqualToString:@"cc"]) DAAddAddresses(cc, value);
        else if ([name isEqualToString:@"bcc"]) DAAddAddresses(bcc, value);
        else if ([name isEqualToString:@"subject"]) { if (!subject) subject = value; }
        else if ([name isEqualToString:@"body"]) { if (!body) body = value; }
        // Other header fields (in-reply-to, keywords, ...) have no equivalent in the apps' schemes.
    }

    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (to.count) d[@"to"] = [to componentsJoinedByString:@","];
    if (cc.count) d[@"cc"] = [cc componentsJoinedByString:@","];
    if (bcc.count) d[@"bcc"] = [bcc componentsJoinedByString:@","];
    if (subject.length) d[@"subject"] = subject;
    if (body.length) d[@"body"] = body;
    return d;
}

// Address lists keep "@" and "," readable; everything else (spaces, "+", "&", "=", "?", "#",
// newlines, non-ASCII) is percent-encoded so no app can mistake it for a separator.
static NSString *DAEA(NSString *s) { return s.length ? DAEncode(s, @"@,") : nil; }
static NSString *DAET(NSString *s) { return s.length ? DAEncode(s, nil) : nil; }

NSURL *DAMailComposeURL(DAMailKind kind, NSDictionary<NSString *, NSString *> *f) {
    if (![f isKindOfClass:[NSDictionary class]]) return nil;
    NSString *to = DAEA(f[@"to"]), *cc = DAEA(f[@"cc"]), *bcc = DAEA(f[@"bcc"]);
    NSString *subject = DAET(f[@"subject"]), *body = DAET(f[@"body"]);
    switch (kind) {
        case DAMailGmail:
            return DAJoin(@"googlegmail:///co", @[@[@"to", to ?: @""], @[@"cc", cc ?: @""], @[@"bcc", bcc ?: @""],
                                                  @[@"subject", subject ?: @""], @[@"body", body ?: @""]]);
        case DAMailOutlook:
            return DAJoin(@"ms-outlook://emails/new", @[@[@"to", to ?: @""], @[@"cc", cc ?: @""], @[@"bcc", bcc ?: @""],
                                                       @[@"subject", subject ?: @""], @[@"body", body ?: @""]]);
        case DAMailSpark:
            return DAJoin(@"readdle-spark://compose", @[@[@"recipient", to ?: @""], @[@"cc", cc ?: @""], @[@"bcc", bcc ?: @""],
                                                       @[@"subject", subject ?: @""], @[@"textbody", body ?: @""]]);
        case DAMailYahoo:
            if (bcc.length) return nil; // ymail compose has no bcc field: keep Apple Mail rather than drop a recipient
            return DAJoin(@"ymail://mail/any/compose", @[@[@"to", to ?: @""], @[@"cc", cc ?: @""],
                                                        @[@"subject", subject ?: @""], @[@"body", body ?: @""]]);
        case DAMailProton: {
            // protonmail://mailto:<user>@<domain>?cc=...  The recipient list sits in the userinfo/host
            // part: everything before the last "@" is the (encoded) userinfo, the rest is the host.
            NSString *base = @"protonmail://mailto:";
            NSString *raw = f[@"to"];
            if (raw.length) {
                NSRange at = [raw rangeOfString:@"@" options:NSBackwardsSearch];
                if (at.location == NSNotFound || at.location == 0 || NSMaxRange(at) >= raw.length) return nil;
                NSString *user = DAEncode([raw substringToIndex:at.location], @"!$&'()*+,;=");
                NSString *host = DAEncode([raw substringFromIndex:NSMaxRange(at)], @"!$&'()*+,;=");
                base = [NSString stringWithFormat:@"%@%@@%@", base, user, host];
            }
            return DAJoin(base, @[@[@"cc", cc ?: @""], @[@"bcc", bcc ?: @""],
                                  @[@"subject", subject ?: @""], @[@"body", body ?: @""]]);
        }
        case DAMailAirmail:
            return DAJoin(@"airmail://compose", @[@[@"to", to ?: @""], @[@"cc", cc ?: @""], @[@"bcc", bcc ?: @""],
                                                 @[@"subject", subject ?: @""], @[@"plainBody", body ?: @""]]);
        case DAMailFastmail:
            return DAJoin(@"fastmail://mail/compose", @[@[@"to", to ?: @""], @[@"cc", cc ?: @""], @[@"bcc", bcc ?: @""],
                                                       @[@"subject", subject ?: @""], @[@"body", body ?: @""]]);
        case DAMailMyMail:
            return DAJoin(@"mymail-mailto://", @[@[@"to", to ?: @""], @[@"cc", cc ?: @""], @[@"bcc", bcc ?: @""],
                                                @[@"subject", subject ?: @""], @[@"body", body ?: @""]]);
    }
    return nil;
}

// ============================================================================================
// Maps
// ============================================================================================

BOOL DAParseCoordinate(NSString *s, double *lat, double *lng) {
    if (![s isKindOfClass:[NSString class]] || s.length == 0) return NO;
    NSScanner *sc = [NSScanner scannerWithString:s];
    sc.charactersToBeSkipped = [NSCharacterSet whitespaceCharacterSet];
    sc.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    double a = 0, b = 0;
    if (![sc scanDouble:&a]) return NO;
    if (![sc scanString:@"," intoString:NULL]) return NO;
    if (![sc scanDouble:&b]) return NO;
    if (!sc.isAtEnd) return NO;
    if (a != a || b != b || a < -90 || a > 90 || b < -180 || b > 180) return NO;
    if (lat) *lat = a;
    if (lng) *lng = b;
    return YES;
}

// "lat,lng" with the original digits but no spaces; nil if not a coordinate.
static NSString *DACoord(NSString *s) {
    if (!DAParseCoordinate(s, NULL, NULL)) return nil;
    return [[s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsJoinedByString:@""];
}

// "lng,lat" (Yandex ll/pt order) from "lat,lng".
static NSString *DALngLat(NSString *c) {
    NSArray *p = [c componentsSeparatedByString:@","];
    return p.count == 2 ? [NSString stringWithFormat:@"%@,%@", p[1], p[0]] : nil;
}

BOOL DAIsAppleMapsURL(NSURL *url) {
    if (![url isKindOfClass:[NSURL class]]) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"maps"] || [scheme isEqualToString:@"map"]) return YES;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
        return [url.host.lowercaseString isEqualToString:@"maps.apple.com"];
    return NO;
}

static BOOL DAIsCurrentLocation(NSString *s) {
    NSString *t = DATrim(s ?: @"");
    return t.length == 0 || [t caseInsensitiveCompare:@"Current Location"] == NSOrderedSame;
}

NSDictionary<NSString *, NSString *> *DAParseAppleMaps(NSURL *url) {
    if (!DAIsAppleMapsURL(url)) return nil;
    NSString *scheme = url.scheme.lowercaseString;
    NSString *abs = url.absoluteString;
    NSString *query = nil, *path = @"";
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        query = url.query;
        path = url.path.lowercaseString ?: @"";
    } else {
        NSRange colon = [abs rangeOfString:@":"];
        NSString *rest = [abs substringFromIndex:NSMaxRange(colon)];
        NSRange hash = [rest rangeOfString:@"#"];
        if (hash.location != NSNotFound) rest = [rest substringToIndex:hash.location];
        NSRange qm = [rest rangeOfString:@"?"];
        if (qm.location != NSNotFound) query = [rest substringFromIndex:NSMaxRange(qm)];
        else {
            if ([rest hasPrefix:@"//"]) rest = [rest substringFromIndex:2];
            if ([rest rangeOfString:@"="].location != NSNotFound) query = rest; // "maps:q=..."
        }
    }

    // Apple Maps links use "+" for spaces (developer.apple.com Map Links examples).
    NSMutableDictionary<NSString *, NSString *> *p = [NSMutableDictionary dictionary];
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        if (!pair.length) continue;
        NSRange eq = [pair rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *name = DADecode([pair substringToIndex:eq.location], YES).lowercaseString;
        NSString *value = DATrim(DADecode([pair substringFromIndex:NSMaxRange(eq)], YES));
        if (name.length && value.length && !p[name]) p[name] = value;
    }

    NSMutableDictionary<NSString *, NSString *> *m = [NSMutableDictionary dictionary];

    // Directions (legacy saddr/daddr/dirflg, current source/destination/mode).
    NSString *saddr = p[@"saddr"] ?: p[@"source"];
    NSString *daddr = p[@"daddr"] ?: p[@"destination"];
    if (DAIsCurrentLocation(saddr)) saddr = nil;
    if (DAIsCurrentLocation(daddr)) daddr = nil;
    if (saddr || daddr || [path isEqualToString:@"/directions"]) {
        if (!saddr && !daddr) return m; // directions with nothing to route: leave it to Apple Maps
        m[@"directions"] = @"1";
        if (saddr) m[@"saddr"] = DACoord(saddr) ?: saddr;
        if (daddr) m[@"daddr"] = DACoord(daddr) ?: daddr;
        NSString *flg = p[@"dirflg"].lowercaseString, *mode = p[@"mode"].lowercaseString;
        NSDictionary *flags = @{ @"d": @"driving", @"w": @"walking", @"r": @"transit", @"c": @"cycling" };
        NSSet *modes = [NSSet setWithObjects:@"driving", @"walking", @"transit", @"cycling", nil];
        if (flg && flags[flg]) m[@"mode"] = flags[flg];
        else if (mode && [modes containsObject:mode]) m[@"mode"] = mode;
    }

    // Place / search.
    NSString *ll = DACoord(p[@"ll"]), *coordinate = DACoord(p[@"coordinate"]);
    NSString *q = p[@"q"] ?: p[@"query"];
    NSString *address = p[@"address"];
    NSString *name = p[@"name"];
    if (coordinate) {                       // maps.apple.com/place?coordinate=..&name=..
        m[@"pin"] = coordinate;
        if (name ?: q) m[@"label"] = name ?: q;
    } else if (ll && q && !address) {       // legacy: "q" with "ll" is the label of the pin at ll
        m[@"pin"] = ll;
        m[@"label"] = q;
    } else if (address || q) {
        m[@"q"] = address ?: q;
    } else if (name && !m[@"directions"]) { // place link with only a name: search for it
        m[@"q"] = name;
    }
    NSString *center = DACoord(p[@"center"]);
    if (!center && ll && !m[@"pin"]) center = ll;
    if (!center) center = DACoord(p[@"sll"]) ?: DACoord(p[@"near"]);
    if (center) m[@"center"] = center;

    NSString *z = p[@"z"];
    if (z.length) {
        NSInteger zi = z.integerValue;
        if (zi >= 1 && zi <= 21) m[@"z"] = [NSString stringWithFormat:@"%ld", (long)zi];
    }
    NSString *t = p[@"t"].lowercaseString;
    NSString *mapType = p[@"map"].lowercaseString;
    if ([@[@"m", @"k", @"h", @"r"] containsObject:t ?: @""]) m[@"t"] = t;
    else if ([mapType isEqualToString:@"satellite"]) m[@"t"] = @"k";
    else if ([mapType isEqualToString:@"hybrid"]) m[@"t"] = @"h";
    else if ([mapType isEqualToString:@"transit"]) m[@"t"] = @"r";
    return m;
}

static NSString *DAME(NSString *s) { return s.length ? DAEncode(s, @",") : @""; }

static NSURL *DAGoogleMaps(NSDictionary<NSString *, NSString *> *m) {
    NSString *views = @"";
    if ([m[@"t"] isEqualToString:@"k"] || [m[@"t"] isEqualToString:@"h"]) views = @"satellite";
    else if ([m[@"t"] isEqualToString:@"r"]) views = @"transit";
    if (m[@"directions"]) {
        NSDictionary *modes = @{ @"driving": @"driving", @"walking": @"walking", @"transit": @"transit", @"cycling": @"bicycling" };
        // A blank saddr/daddr means the current location (Google Maps URL scheme docs).
        return DAJoin(@"comgooglemaps://", @[@[@"saddr", DAME(m[@"saddr"])], @[@"daddr", DAME(m[@"daddr"])],
                                             @[@"directionsmode", modes[m[@"mode"]] ?: @""]]);
    }
    NSString *q = nil, *center = m[@"center"];
    if (m[@"pin"]) { q = m[@"pin"]; if (!center) center = m[@"pin"]; } // exact spot; Google has no label parameter
    else if (m[@"q"]) q = m[@"q"];
    else if (!center) return nil;
    return DAJoin(@"comgooglemaps://", @[@[@"q", DAME(q)], @[@"center", DAME(center)],
                                         @[@"zoom", m[@"z"] ?: @""], @[@"views", views]]);
}

static NSURL *DAWaze(NSDictionary<NSString *, NSString *> *m) {
    if (m[@"directions"]) {
        // Waze always routes from the current position.
        NSString *d = m[@"daddr"];
        if (!d || m[@"saddr"]) return nil;
        if (DACoord(d)) return DAJoin(@"waze://", @[@[@"ll", DAME(d)], @[@"navigate", @"yes"]]);
        return DAJoin(@"waze://", @[@[@"q", DAME(d)], @[@"navigate", @"yes"]]);
    }
    if (m[@"pin"]) return DAJoin(@"waze://", @[@[@"ll", DAME(m[@"pin"])]]);
    if (m[@"q"]) return DAJoin(@"waze://", @[@[@"q", DAME(m[@"q"])], @[@"ll", DAME(m[@"center"])]]);
    if (m[@"center"]) return DAJoin(@"waze://", @[@[@"ll", DAME(m[@"center"])]]);
    return nil;
}

static NSURL *DACitymapper(NSDictionary<NSString *, NSString *> *m) {
    // citymapper://directions needs the destination as a coordinate (endcoord); the start is
    // optional (current location) but must be a coordinate too when given.
    if (m[@"directions"]) {
        NSString *d = DACoord(m[@"daddr"]);
        if (!d) return nil;
        NSString *s = nil;
        if (m[@"saddr"]) { s = DACoord(m[@"saddr"]); if (!s) return nil; }
        return DAJoin(@"citymapper://directions", @[@[@"startcoord", DAME(s)], @[@"endcoord", DAME(d)]]);
    }
    if (m[@"pin"]) return DAJoin(@"citymapper://directions", @[@[@"endcoord", DAME(m[@"pin"])], @[@"endname", DAME(m[@"label"])]]);
    return nil;
}

static NSURL *DAYandex(NSDictionary<NSString *, NSString *> *m) {
    NSString *base = @"yandexmaps://maps.yandex.ru/";
    NSString *l = @"";
    if ([m[@"t"] isEqualToString:@"k"]) l = @"sat";
    else if ([m[@"t"] isEqualToString:@"h"]) l = @"sat,skl";
    NSString *z = @"";
    if (m[@"z"]) z = [NSString stringWithFormat:@"%ld", (long)MAX(1, MIN(18, m[@"z"].integerValue))];
    if (m[@"directions"]) {
        // rtext=<lat,lng>~<lat,lng>; an empty start means the current location.
        NSString *d = DACoord(m[@"daddr"]);
        NSString *s = m[@"saddr"] ? DACoord(m[@"saddr"]) : @"";
        if (d && s) {
            NSDictionary *rtt = @{ @"driving": @"auto", @"transit": @"mt", @"walking": @"pd" };
            return DAJoin(base, @[@[@"rtext", [NSString stringWithFormat:@"%@~%@", s, d]], @[@"rtt", rtt[m[@"mode"]] ?: @""]]);
        }
        if (!m[@"saddr"] && m[@"daddr"] && !d) return DAJoin(base, @[@[@"text", DAME(m[@"daddr"])]]); // address: search for it
        return nil;
    }
    if (m[@"pin"]) return DAJoin(base, @[@[@"pt", DALngLat(m[@"pin"])], @[@"ll", DALngLat(m[@"center"] ?: m[@"pin"])], @[@"z", z], @[@"l", l]]);
    if (m[@"q"]) return DAJoin(base, @[@[@"text", DAME(m[@"q"])], @[@"ll", m[@"center"] ? DALngLat(m[@"center"]) : @""], @[@"z", z], @[@"l", l]]);
    if (m[@"center"]) return DAJoin(base, @[@[@"ll", DALngLat(m[@"center"])], @[@"z", z], @[@"l", l]]);
    return nil;
}

static NSURL *DAOrganic(NSString *scheme, NSDictionary<NSString *, NSString *> *m) {
    NSString *map = [scheme stringByAppendingString:@"://map"];
    NSString *search = [scheme stringByAppendingString:@"://search"];
    if (m[@"directions"]) {
        NSString *d = DACoord(m[@"daddr"]), *s = m[@"saddr"] ? DACoord(m[@"saddr"]) : nil;
        if (d && s) {
            // route?sll=&saddr=&dll=&daddr=&type= (all five, in this order, both points as coordinates)
            NSDictionary *types = @{ @"driving": @"vehicle", @"walking": @"pedestrian", @"cycling": @"bicycle", @"transit": @"transit" };
            return DAJoin([scheme stringByAppendingString:@"://route"],
                          @[@[@"sll", s], @[@"saddr", DAME(s)], @[@"dll", d], @[@"daddr", DAME(d)],
                            @[@"type", types[m[@"mode"]] ?: @"vehicle"]]);
        }
        if (!m[@"saddr"] && d) return DAJoin(map, @[@[@"ll", d]]);
        if (!m[@"saddr"] && m[@"daddr"]) return DAJoin(search, @[@[@"query", DAME(m[@"daddr"])]]);
        return nil;
    }
    if (m[@"pin"]) return DAJoin(map, @[@[@"ll", m[@"pin"]], @[@"n", DAME(m[@"label"])]]);
    if (m[@"q"]) return DAJoin(search, @[@[@"query", DAME(m[@"q"])], @[@"cll", m[@"center"] ?: @""]]);
    if (m[@"center"]) return DAJoin(map, @[@[@"ll", m[@"center"]]]);
    return nil;
}

NSURL *DAMapsURL(DAMapsKind kind, NSDictionary<NSString *, NSString *> *m) {
    if (![m isKindOfClass:[NSDictionary class]] || m.count == 0) return nil;
    switch (kind) {
        case DAMapsGoogle:     return DAGoogleMaps(m);
        case DAMapsWaze:       return DAWaze(m);
        case DAMapsCitymapper: return DACitymapper(m);
        case DAMapsYandex:     return DAYandex(m);
        case DAMapsOrganic:    return DAOrganic(@"om", m);
        case DAMapsMapsMe:     return DAOrganic(@"mapsme", m);
    }
    return nil;
}
