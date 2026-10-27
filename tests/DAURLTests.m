// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 itsAllexB

// Unit tests for the URL translation in DAURL.m. Runs on the Mac: tests/run.sh

#import <Foundation/Foundation.h>
#import "../DAURL.h"

static int gFail = 0, gPass = 0;

static void EQ(NSString *what, id got, id want) {
    BOOL ok = (got == nil && want == nil) || [got isEqual:want];
    if (ok) { gPass++; return; }
    gFail++;
    printf("FAIL %s\n  got:  %s\n  want: %s\n", what.UTF8String, [[got description] UTF8String], [[want description] UTF8String]);
}

static NSString *S(NSURL *u) { return u.absoluteString; }
static NSURL *U(NSString *s) { return [NSURL URLWithString:s]; }

// Decodes a generated URL's query the way an app would (NSURLComponents), for round-trip checks.
static NSDictionary *Q(NSURL *u) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *i in [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO].queryItems) d[i.name] = i.value ?: @"";
    return d;
}

static NSString *Mail(DAMailKind k, NSString *mailto) { return S(DAMailComposeURL(k, DAParseMailto(U(mailto)))); }
static NSString *Maps(DAMapsKind k, NSString *link) { return S(DAMapsURL(k, DAParseAppleMaps(U(link)))); }

int main(void) {
    @autoreleasepool {
        // ---------------- mailto parsing ----------------
        EQ(@"parse simple", DAParseMailto(U(@"mailto:a@x.com")), (@{ @"to": @"a@x.com" }));
        EQ(@"parse full",
           DAParseMailto(U(@"mailto:a@x.com,%20b@y.com?cc=c@z.com&bcc=d@w.com&subject=Hello%20World%20%26%20more&body=Line1%0D%0ALine2%20a+b%3Dc")),
           (@{ @"to": @"a@x.com,b@y.com", @"cc": @"c@z.com", @"bcc": @"d@w.com",
               @"subject": @"Hello World & more", @"body": @"Line1\r\nLine2 a+b=c" }));
        EQ(@"parse to in query, repeated", DAParseMailto(U(@"mailto:?to=a@x.com&to=b@y.com")), (@{ @"to": @"a@x.com,b@y.com" }));
        EQ(@"parse both path and to header", DAParseMailto(U(@"mailto:a@x.com?to=b@y.com")), (@{ @"to": @"a@x.com,b@y.com" }));
        EQ(@"parse header case-insensitive", DAParseMailto(U(@"mailto:a@x.com?SUBJECT=Hi&Body=Yo&CC=c@z.com")),
           (@{ @"to": @"a@x.com", @"subject": @"Hi", @"body": @"Yo", @"cc": @"c@z.com" }));
        EQ(@"parse plus is literal", DAParseMailto(U(@"mailto:a%2Btag@x.com?subject=1+1")), (@{ @"to": @"a+tag@x.com", @"subject": @"1+1" }));
        EQ(@"parse empty", DAParseMailto(U(@"mailto:")), (@{}));
        EQ(@"parse not mailto", DAParseMailto(U(@"http://a.com")), nil);
        EQ(@"parse unknown headers ignored", DAParseMailto(U(@"mailto:a@x.com?in-reply-to=%3Cid%3E&keywords=k")), (@{ @"to": @"a@x.com" }));
        EQ(@"parse utf8", DAParseMailto(U(@"mailto:a@x.com?subject=Caf%C3%A9%20%E2%98%95")), (@{ @"to": @"a@x.com", @"subject": @"Café ☕" }));

        NSString *full = @"mailto:a@x.com,b@y.com?cc=c@z.com&bcc=d@w.com&subject=Hello%20World%20%26%20more&body=Line1%0D%0ALine2%20a+b%3Dc";
        // ---------------- mail apps ----------------
        EQ(@"gmail simple", Mail(DAMailGmail, @"mailto:a@x.com"), @"googlegmail:///co?to=a@x.com");
        EQ(@"gmail full", Mail(DAMailGmail, full),
           @"googlegmail:///co?to=a@x.com,b@y.com&cc=c@z.com&bcc=d@w.com&subject=Hello%20World%20%26%20more&body=Line1%0D%0ALine2%20a%2Bb%3Dc");
        EQ(@"gmail empty", Mail(DAMailGmail, @"mailto:"), @"googlegmail:///co");
        EQ(@"outlook full", Mail(DAMailOutlook, full),
           @"ms-outlook://emails/new?to=a@x.com,b@y.com&cc=c@z.com&bcc=d@w.com&subject=Hello%20World%20%26%20more&body=Line1%0D%0ALine2%20a%2Bb%3Dc");
        EQ(@"spark full", Mail(DAMailSpark, full),
           @"readdle-spark://compose?recipient=a@x.com,b@y.com&cc=c@z.com&bcc=d@w.com&subject=Hello%20World%20%26%20more&textbody=Line1%0D%0ALine2%20a%2Bb%3Dc");
        EQ(@"yahoo with bcc refused", Mail(DAMailYahoo, full), nil);
        EQ(@"yahoo without bcc", Mail(DAMailYahoo, @"mailto:a@x.com?cc=c@z.com&subject=Hi%20there&body=x"),
           @"ymail://mail/any/compose?to=a@x.com&cc=c@z.com&subject=Hi%20there&body=x");
        EQ(@"proton single", Mail(DAMailProton, @"mailto:a@x.com"), @"protonmail://mailto:a@x.com");
        EQ(@"proton full", Mail(DAMailProton, full),
           @"protonmail://mailto:a%40x.com,b@y.com?cc=c@z.com&bcc=d@w.com&subject=Hello%20World%20%26%20more&body=Line1%0D%0ALine2%20a%2Bb%3Dc");
        EQ(@"proton no recipient", Mail(DAMailProton, @"mailto:?subject=Hi"), @"protonmail://mailto:?subject=Hi");
        EQ(@"airmail full", Mail(DAMailAirmail, full),
           @"airmail://compose?to=a@x.com,b@y.com&cc=c@z.com&bcc=d@w.com&subject=Hello%20World%20%26%20more&plainBody=Line1%0D%0ALine2%20a%2Bb%3Dc");
        EQ(@"fastmail full", Mail(DAMailFastmail, full),
           @"fastmail://mail/compose?to=a@x.com,b@y.com&cc=c@z.com&bcc=d@w.com&subject=Hello%20World%20%26%20more&body=Line1%0D%0ALine2%20a%2Bb%3Dc");
        EQ(@"mymail simple", Mail(DAMailMyMail, @"mailto:a@x.com?subject=S"), @"mymail-mailto://?to=a@x.com&subject=S");
        EQ(@"gmail plus address", Mail(DAMailGmail, @"mailto:a%2Btag@x.com"), @"googlegmail:///co?to=a%2Btag@x.com");
        EQ(@"gmail utf8", Mail(DAMailGmail, @"mailto:a@x.com?subject=Caf%C3%A9%20%E2%98%95"),
           @"googlegmail:///co?to=a@x.com&subject=Caf%C3%A9%20%E2%98%95");

        // Round trip: what an app decodes equals what the mailto link carried.
        NSDictionary *rt = Q(DAMailComposeURL(DAMailGmail, DAParseMailto(U(full))));
        EQ(@"roundtrip gmail", rt, (@{ @"to": @"a@x.com,b@y.com", @"cc": @"c@z.com", @"bcc": @"d@w.com",
                                      @"subject": @"Hello World & more", @"body": @"Line1\r\nLine2 a+b=c" }));
        rt = Q(DAMailComposeURL(DAMailSpark, DAParseMailto(U(full))));
        EQ(@"roundtrip spark", rt, (@{ @"recipient": @"a@x.com,b@y.com", @"cc": @"c@z.com", @"bcc": @"d@w.com",
                                      @"subject": @"Hello World & more", @"textbody": @"Line1\r\nLine2 a+b=c" }));
        NSURLComponents *pc = [NSURLComponents componentsWithURL:DAMailComposeURL(DAMailProton, DAParseMailto(U(full))) resolvingAgainstBaseURL:NO];
        EQ(@"roundtrip proton recipients", [NSString stringWithFormat:@"%@@%@", pc.password, pc.host], @"a@x.com,b@y.com");

        // ---------------- Apple Maps parsing ----------------
        EQ(@"maps detect http", @(DAIsAppleMapsURL(U(@"http://maps.apple.com/?q=x"))), @YES);
        EQ(@"maps detect https caps", @(DAIsAppleMapsURL(U(@"https://MAPS.apple.com/?q=x"))), @YES);
        EQ(@"maps detect maps:", @(DAIsAppleMapsURL(U(@"maps:?q=x"))), @YES);
        EQ(@"maps detect map://", @(DAIsAppleMapsURL(U(@"map://?q=x"))), @YES);
        EQ(@"maps detect other host", @(DAIsAppleMapsURL(U(@"https://apple.com/maps/"))), @NO);
        EQ(@"parse q", DAParseAppleMaps(U(@"http://maps.apple.com/?q=Mexican+Restaurant")), (@{ @"q": @"Mexican Restaurant" }));
        EQ(@"parse ll+q = pin", DAParseAppleMaps(U(@"http://maps.apple.com/?ll=50.894967,4.341626&q=Atomium&z=17")),
           (@{ @"pin": @"50.894967,4.341626", @"label": @"Atomium", @"z": @"17" }));
        EQ(@"parse directions", DAParseAppleMaps(U(@"http://maps.apple.com/?saddr=Cupertino&daddr=San+Francisco&dirflg=r")),
           (@{ @"directions": @"1", @"saddr": @"Cupertino", @"daddr": @"San Francisco", @"mode": @"transit" }));
        EQ(@"parse current location enc", DAParseAppleMaps(U(@"maps://?saddr=Current%20Location&daddr=37.331,%20-122.031&dirflg=w")),
           (@{ @"directions": @"1", @"daddr": @"37.331,-122.031", @"mode": @"walking" }));
        EQ(@"parse new place", DAParseAppleMaps(U(@"https://maps.apple.com/place?coordinate=35.6586,139.7454&name=Tokyo%20Tower")),
           (@{ @"pin": @"35.6586,139.7454", @"label": @"Tokyo Tower" }));
        EQ(@"parse new directions", DAParseAppleMaps(U(@"https://maps.apple.com/directions?destination=Tokyo+Tower&mode=walking")),
           (@{ @"directions": @"1", @"daddr": @"Tokyo Tower", @"mode": @"walking" }));
        EQ(@"parse new search", DAParseAppleMaps(U(@"https://maps.apple.com/search?query=coffee&center=35.66,139.73&map=satellite")),
           (@{ @"q": @"coffee", @"center": @"35.66,139.73", @"t": @"k" }));
        EQ(@"parse sll + t", DAParseAppleMaps(U(@"maps:?q=pizza&sll=50.894967,4.341626&z=10&t=k")),
           (@{ @"q": @"pizza", @"center": @"50.894967,4.341626", @"z": @"10", @"t": @"k" }));
        EQ(@"parse address", DAParseAppleMaps(U(@"maps://?address=1+Infinite+Loop,+Cupertino,+CA")),
           (@{ @"q": @"1 Infinite Loop, Cupertino, CA" }));
        EQ(@"parse no query maps:q=", DAParseAppleMaps(U(@"maps:q=Paris")), (@{ @"q": @"Paris" }));
        EQ(@"parse ll only = center", DAParseAppleMaps(U(@"maps:?ll=48.8584,2.2945")), (@{ @"center": @"48.8584,2.2945" }));
        EQ(@"parse opaque", DAParseAppleMaps(U(@"maps:?auid=123456&_ext=abc")), (@{}));
        EQ(@"parse bad coordinate", DAParseAppleMaps(U(@"maps:?ll=91,0&q=x")), (@{ @"q": @"x" }));

        // ---------------- Google Maps ----------------
        EQ(@"google search", Maps(DAMapsGoogle, @"http://maps.apple.com/?q=Mexican+Restaurant"), @"comgooglemaps://?q=Mexican%20Restaurant");
        EQ(@"google pin", Maps(DAMapsGoogle, @"http://maps.apple.com/?ll=50.894967,4.341626&q=Atomium&z=17"),
           @"comgooglemaps://?q=50.894967,4.341626&center=50.894967,4.341626&zoom=17");
        EQ(@"google directions", Maps(DAMapsGoogle, @"http://maps.apple.com/?saddr=Cupertino&daddr=San+Francisco&dirflg=r"),
           @"comgooglemaps://?saddr=Cupertino&daddr=San%20Francisco&directionsmode=transit");
        EQ(@"google directions from here", Maps(DAMapsGoogle, @"maps://?saddr=Current%20Location&daddr=37.331,-122.031&dirflg=w"),
           @"comgooglemaps://?daddr=37.331,-122.031&directionsmode=walking");
        EQ(@"google directions cycling", Maps(DAMapsGoogle, @"https://maps.apple.com/directions?destination=A&mode=cycling"),
           @"comgooglemaps://?daddr=A&directionsmode=bicycling");
        EQ(@"google search near", Maps(DAMapsGoogle, @"maps:?q=pizza&sll=50.894967,4.341626&z=10&t=k"),
           @"comgooglemaps://?q=pizza&center=50.894967,4.341626&zoom=10&views=satellite");
        EQ(@"google address", Maps(DAMapsGoogle, @"maps://?address=1+Infinite+Loop,+Cupertino,+CA"),
           @"comgooglemaps://?q=1%20Infinite%20Loop,%20Cupertino,%20CA");
        EQ(@"google center only", Maps(DAMapsGoogle, @"maps:?ll=48.8584,2.2945&t=r"), @"comgooglemaps://?center=48.8584,2.2945&views=transit");
        EQ(@"google place", Maps(DAMapsGoogle, @"https://maps.apple.com/place?coordinate=35.6586,139.7454&name=Tokyo%20Tower"),
           @"comgooglemaps://?q=35.6586,139.7454&center=35.6586,139.7454");
        EQ(@"google opaque -> stock", Maps(DAMapsGoogle, @"maps:?auid=123456"), nil);
        EQ(@"google ampersand in query", Maps(DAMapsGoogle, @"maps:?q=Barnes+%26+Noble"), @"comgooglemaps://?q=Barnes%20%26%20Noble");
        EQ(@"google multi-stop kept", Maps(DAMapsGoogle, @"maps:?daddr=A+to:B"), @"comgooglemaps://?daddr=A%20to%3AB");

        // ---------------- Waze ----------------
        EQ(@"waze directions text", Maps(DAMapsWaze, @"http://maps.apple.com/?daddr=San+Francisco"), @"waze://?q=San%20Francisco&navigate=yes");
        EQ(@"waze directions coord", Maps(DAMapsWaze, @"maps:?daddr=37.331,-122.031"), @"waze://?ll=37.331,-122.031&navigate=yes");
        EQ(@"waze from elsewhere -> stock", Maps(DAMapsWaze, @"maps:?saddr=A&daddr=B"), nil);
        EQ(@"waze pin", Maps(DAMapsWaze, @"maps:?ll=50.894967,4.341626&q=Atomium"), @"waze://?ll=50.894967,4.341626");
        EQ(@"waze search near", Maps(DAMapsWaze, @"maps:?q=pizza&sll=50.89,4.34"), @"waze://?q=pizza&ll=50.89,4.34");

        // ---------------- Citymapper ----------------
        EQ(@"citymapper coord", Maps(DAMapsCitymapper, @"maps:?daddr=51.5,-0.12"), @"citymapper://directions?endcoord=51.5,-0.12");
        EQ(@"citymapper both", Maps(DAMapsCitymapper, @"maps:?saddr=51.4,-0.1&daddr=51.5,-0.12"),
           @"citymapper://directions?startcoord=51.4,-0.1&endcoord=51.5,-0.12");
        EQ(@"citymapper text -> stock", Maps(DAMapsCitymapper, @"maps:?daddr=Big+Ben"), nil);
        EQ(@"citymapper pin", Maps(DAMapsCitymapper, @"maps:?ll=51.5007,-0.1246&q=Big+Ben"),
           @"citymapper://directions?endcoord=51.5007,-0.1246&endname=Big%20Ben");
        EQ(@"citymapper search -> stock", Maps(DAMapsCitymapper, @"maps:?q=pizza"), nil);

        // ---------------- Yandex ----------------
        EQ(@"yandex pin lng,lat", Maps(DAMapsYandex, @"maps:?ll=55.7558,37.6173&q=Kremlin&z=20"),
           @"yandexmaps://maps.yandex.ru/?pt=37.6173,55.7558&ll=37.6173,55.7558&z=18");
        EQ(@"yandex route from here", Maps(DAMapsYandex, @"maps:?daddr=59.93,30.31&dirflg=w"),
           @"yandexmaps://maps.yandex.ru/?rtext=~59.93,30.31&rtt=pd");
        EQ(@"yandex route", Maps(DAMapsYandex, @"maps:?saddr=59.96,30.24&daddr=59.89,30.29&dirflg=r"),
           @"yandexmaps://maps.yandex.ru/?rtext=59.96,30.24~59.89,30.29&rtt=mt");
        EQ(@"yandex search", Maps(DAMapsYandex, @"maps:?q=cafe&sll=59.95,30.31&t=k"),
           @"yandexmaps://maps.yandex.ru/?text=cafe&ll=30.31,59.95&l=sat");

        // ---------------- Organic Maps / MAPS.ME ----------------
        EQ(@"om pin", Maps(DAMapsOrganic, @"https://maps.apple.com/place?coordinate=35.6586,139.7454&name=Tokyo%20Tower"),
           @"om://map?ll=35.6586,139.7454&n=Tokyo%20Tower");
        EQ(@"om search", Maps(DAMapsOrganic, @"maps:?q=coffee&sll=35.66,139.73"), @"om://search?query=coffee&cll=35.66,139.73");
        EQ(@"om route", Maps(DAMapsOrganic, @"maps:?saddr=1,2&daddr=3,4&dirflg=w"),
           @"om://route?sll=1,2&saddr=1,2&dll=3,4&daddr=3,4&type=pedestrian");
        EQ(@"om directions to coord", Maps(DAMapsOrganic, @"maps:?daddr=3,4"), @"om://map?ll=3,4");
        EQ(@"mapsme pin", Maps(DAMapsMapsMe, @"maps:?ll=3,4&q=X"), @"mapsme://map?ll=3,4&n=X");

        // ---------------- Browsers ----------------
        EQ(@"firefox", S(DABrowserURL(DABrowserStyleOpenURL, @"firefox", nil, U(@"https://example.com/a?b=c&d=e#f"))),
           @"firefox://open-url?url=https%3A%2F%2Fexample.com%2Fa%3Fb%3Dc%26d%3De%23f");
        EQ(@"chrome https", S(DABrowserURL(DABrowserStyleReplace, @"googlechrome", @"googlechromes", U(@"https://example.com/x"))),
           @"googlechromes://example.com/x");
        EQ(@"chrome http", S(DABrowserURL(DABrowserStyleReplace, @"googlechrome", @"googlechromes", U(@"http://example.com/x"))),
           @"googlechrome://example.com/x");
        EQ(@"ddg", S(DABrowserURL(DABrowserStylePrefix, @"ddgQuickLink", nil, U(@"https://example.com/"))), @"ddgQuickLink://https://example.com/");
        EQ(@"browser ignores mailto", S(DABrowserURL(DABrowserStyleOpenURL, @"firefox", nil, U(@"mailto:a@x.com"))), nil);

        // ---------------- coordinates ----------------
        EQ(@"coord ok", @(DAParseCoordinate(@"-33.8688, 151.2093", NULL, NULL)), @YES);
        EQ(@"coord lat range", @(DAParseCoordinate(@"91,0", NULL, NULL)), @NO);
        EQ(@"coord text", @(DAParseCoordinate(@"Paris, France", NULL, NULL)), @NO);
        EQ(@"coord trailing", @(DAParseCoordinate(@"1,2,3", NULL, NULL)), @NO);
    }
    printf("%d passed, %d failed\n", gPass, gFail);
    return gFail ? 1 : 0;
}
