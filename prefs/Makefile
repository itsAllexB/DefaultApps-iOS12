# SPDX-License-Identifier: GPL-3.0-or-later
TARGET := iphone:clang:14.5:12.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DefaultBrowserPrefs
DefaultBrowserPrefs_FILES = DBRootListController.m
DefaultBrowserPrefs_FRAMEWORKS = UIKit
DefaultBrowserPrefs_PRIVATE_FRAMEWORKS = Preferences
DefaultBrowserPrefs_INSTALL_PATH = /Library/PreferenceBundles
DefaultBrowserPrefs_CFLAGS = -fobjc-arc -I..

include $(THEOS_MAKE_PATH)/bundle.mk
