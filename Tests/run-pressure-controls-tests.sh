#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/PerformanceHUD-pressure-controls-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
compile_tests() {
    set -- -swift-version 5 -parse-as-library
    for source in "$ROOT"/PerformanceHUD/*.swift; do
        case "$source" in
            */PerformanceHUDApp.swift|*/AppDelegate.swift|*/HUDUpdater.swift) continue ;;
        esac
        set -- "$@" "$source"
    done
    xcrun swiftc "$@" "$ROOT/PowerHelperShared/"*.swift "$ROOT/Tests/PressureControlsTests.swift" -o "$OUT/tests"
}
compile_tests
"$OUT/tests"
