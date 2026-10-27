#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds the empty DefaultBrowser 2.0.2 package that moves DefaultBrowser users to DefaultApps.
# Output: packages/com.itsallexb.defaultbrowser_<version>_iphoneos-arm.deb (needs dpkg-deb).
set -e
cd "$(dirname "$0")/.."
ver=$(sed -n 's/^Version: //p' transitional/defaultbrowser/DEBIAN/control)
mkdir -p packages
dpkg-deb -Zxz --root-owner-group -b transitional/defaultbrowser "packages/com.itsallexb.defaultbrowser_${ver}_iphoneos-arm.deb"
