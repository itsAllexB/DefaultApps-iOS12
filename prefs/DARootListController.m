// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 itsAllexB

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "DAApps.h"

@interface PSSpecifier (DAPrivate)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end

@interface DARootListController : PSListController
@end

static NSString *const kDADefaultTitle = @"Default (Apple)";

@implementation DARootListController

- (PSSpecifier *)specifierForID:(NSString *)identifier in:(NSArray *)specs {
    for (PSSpecifier *s in specs) if ([s.identifier isEqualToString:identifier]) return s;
    return nil;
}

// Fills one picker: "Default (Apple)" + installed apps (+ the saved choice if it was removed).
- (void)fillPicker:(NSString *)key group:(NSString *)groupID in:(NSArray *)specs
             count:(size_t)count
              info:(void (^)(size_t i, NSString **bid, NSString **name, BOOL *usable))info
           appleIs:(NSString *)appleName kind:(NSString *)kind {
    PSSpecifier *picker = [self specifierForID:key in:specs];
    if (!picker) return;
    NSMutableArray *values = [NSMutableArray arrayWithObject:kDAApple];
    NSMutableArray *titles = [NSMutableArray arrayWithObject:kDADefaultTitle];
    NSMutableArray *missing = [NSMutableArray array];
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < count; i++) {
        NSString *bid = nil, *name = nil; BOOL usable = NO;
        info(i, &bid, &name, &usable);
        names[bid] = name;
        if (usable) { [values addObject:bid]; [titles addObject:name]; }
        else [missing addObject:name];
    }
    NSString *current = [self readPreferenceValue:picker];
    if (![current isKindOfClass:[NSString class]]) current = kDAApple;
    BOOL currentListed = [values containsObject:current];
    if (!currentListed) {
        [values addObject:current];
        [titles addObject:[NSString stringWithFormat:@"%@ (not installed)", names[current] ?: current]];
    }
    [picker setValues:values titles:titles];

    NSString *footer;
    NSUInteger installed = values.count - 1 - (currentListed ? 0 : 1);
    if (installed == 0)
        footer = [NSString stringWithFormat:@"No supported %@ is installed, so these links keep opening in %@.", kind, appleName];
    else
        footer = [NSString stringWithFormat:@"Only %@s installed on this device are listed.", kind];
    if (!currentListed && ![current isEqualToString:kDAApple])
        footer = [footer stringByAppendingFormat:@" The chosen app is not installed, so %@ is used for now.", appleName];
    if (missing.count)
        footer = [footer stringByAppendingFormat:@" Also supported: %@.", [missing componentsJoinedByString:@", "]];
    [[self specifierForID:groupID in:specs] setProperty:footer forKey:@"footerText"];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        [self fillPicker:@"browser" group:@"browserGroup" in:specs count:kDABrowserCount
                    info:^(size_t i, NSString **bid, NSString **name, BOOL *usable) {
                        *bid = @(kDABrowsers[i].bundleID); *name = @(kDABrowsers[i].name);
                        *usable = DABrowserUsable(&kDABrowsers[i]);
                    } appleIs:@"Safari" kind:@"browser"];
        [self fillPicker:@"mail" group:@"mailGroup" in:specs count:kDAMailCount
                    info:^(size_t i, NSString **bid, NSString **name, BOOL *usable) {
                        *bid = @(kDAMailApps[i].bundleID); *name = @(kDAMailApps[i].name);
                        *usable = DAMailUsable(&kDAMailApps[i]);
                    } appleIs:@"Mail" kind:@"mail app"];
        [self fillPicker:@"maps" group:@"mapsGroup" in:specs count:kDAMapsCount
                    info:^(size_t i, NSString **bid, NSString **name, BOOL *usable) {
                        *bid = @(kDAMapsApps[i].bundleID); *name = @(kDAMapsApps[i].name);
                        *usable = DAMapsUsable(&kDAMapsApps[i]);
                    } appleIs:@"Maps" kind:@"maps app"];
        _specifiers = specs;
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    // Re-scan installed apps each time the pane is shown.
    _specifiers = nil;
    [self reloadSpecifiers];
    [super viewWillAppear:animated];
}

@end
