#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/PerformanceHUD-menu-bar-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
compile_tests() {
    set -- -swift-version 5 -parse-as-library
    for source in "$ROOT"/PerformanceHUD/*.swift; do
        case "$source" in
            */PerformanceHUDApp.swift|*/AppDelegate.swift|*/HUDUpdater.swift) continue ;;
        esac
        set -- "$@" "$source"
    done
    # A dedicated process name isolates UserDefaults.standard used by native controls.
    xcrun swiftc "$@" "$ROOT"/PowerHelperShared/*.swift "$ROOT/Tests/MenuBarTests.swift" -o "$OUT/menu-bar-tests"
}
compile_tests
"$OUT/menu-bar-tests"
