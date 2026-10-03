#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/PerformanceHUD-menu-layout-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$ROOT/PerformanceHUD/HUDMenuLayout.swift" \
  "$ROOT/PerformanceHUD/HUDBackground.swift" \
  "$ROOT/Tests/MenuLayoutTests.swift" -o "$OUT/tests"
"$OUT/tests"
