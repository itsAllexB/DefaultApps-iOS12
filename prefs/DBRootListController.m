// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 itsAllexB

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "DBBrowsers.h"

@interface PSSpecifier (DBPrivate)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end

@interface DBRootListController : PSListController
@end

@implementation DBRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        NSMutableArray *values = [NSMutableArray array], *titles = [NSMutableArray array];
        NSMutableArray *missing = [NSMutableArray array];
        for (size_t i = 0; i < kDBBrowserCount; i++) {
            if (DBBrowserUsable(&kDBBrowsers[i])) {
                [values addObject:@(kDBBrowsers[i].bundleID)];
                [titles addObject:@(kDBBrowsers[i].name)];
            } else {
                [missing addObject:@(kDBBrowsers[i].name)];
            }
        }
        NSString *current = [self readPreferenceValue:[self specifierForID:@"browser" in:specs]];
        if (![current isKindOfClass:[NSString class]]) current = @"org.mozilla.ios.Firefox";
        BOOL currentInstalled = [values containsObject:current];
        if (!currentInstalled) {
            const DBBrowser *b = DBBrowserForBundleID(current);
            [values addObject:current];
            [titles addObject:[NSString stringWithFormat:@"%@ (not installed)", b ? @(b->name) : current]];
        }
        PSSpecifier *browser = [self specifierForID:@"browser" in:specs];
        [browser setValues:values titles:titles];

        PSSpecifier *group = [self specifierForID:@"browserGroup" in:specs];
        NSString *footer = values.count > (currentInstalled ? 0 : 1)
            ? @"Only browsers installed on this iPad are listed."
            : @"No supported browser is installed, so links keep opening in Safari.";
        if (missing.count) footer = [footer stringByAppendingFormat:@" Also supported when installed: %@.", [missing componentsJoinedByString:@", "]];
        [group setProperty:footer forKey:@"footerText"];
        _specifiers = specs;
    }
    return _specifiers;
}

- (PSSpecifier *)specifierForID:(NSString *)identifier in:(NSArray *)specs {
    for (PSSpecifier *s in specs) if ([s.identifier isEqualToString:identifier]) return s;
    return nil;
}

- (void)viewWillAppear:(BOOL)animated {
    // Re-scan installed browsers each time the pane is shown.
    _specifiers = nil;
    [self reloadSpecifiers];
    [super viewWillAppear:animated];
}

@end
