#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/PerformanceHUD-update-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
    "$ROOT/PerformanceHUD/HUDUpdatePolicy.swift" "$ROOT/Tests/UpdatePolicyTests.swift" -o "$OUT/tests"
"$OUT/tests" "$ROOT/Config/Info.plist"
