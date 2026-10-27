# SPDX-License-Identifier: GPL-3.0-or-later
TARGET := iphone:clang:14.5:12.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DefaultAppsPrefs
DefaultAppsPrefs_FILES = DARootListController.m
DefaultAppsPrefs_FRAMEWORKS = UIKit
DefaultAppsPrefs_PRIVATE_FRAMEWORKS = Preferences
DefaultAppsPrefs_INSTALL_PATH = /Library/PreferenceBundles
DefaultAppsPrefs_CFLAGS = -fobjc-arc -I..

include $(THEOS_MAKE_PATH)/bundle.mk
