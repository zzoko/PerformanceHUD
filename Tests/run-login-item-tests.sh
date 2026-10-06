#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/PerformanceHUD-login-item-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$OUT/modules" \
  "$ROOT/PerformanceHUD/HUDLoginItem.swift" \
  "$ROOT/Tests/LoginItemTests.swift" -o "$OUT/tests"
"$OUT/tests"
