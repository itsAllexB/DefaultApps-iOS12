#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds and runs the URL translation unit tests on the Mac.
set -e
cd "$(dirname "$0")"
OUT="${TMPDIR:-/tmp}/daurl-tests"
clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -framework Foundation ../DAURL.m DAURLTests.m -o "$OUT"
"$OUT"
