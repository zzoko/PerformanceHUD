#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/PerformanceHUD-auto-hide-animation-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
compile_tests() {
  set -- -swift-version 5 -parse-as-library
  for source in "$ROOT"/PerformanceHUD/*.swift; do
    case "$source" in
      */PerformanceHUDApp.swift|*/AppDelegate.swift|*/HUDUpdater.swift) continue ;;
    esac
    set -- "$@" "$source"
  done
  xcrun swiftc "$@" "$ROOT"/PowerHelperShared/*.swift "$ROOT/Tests/AutoHideAnimationTests.swift" -o "$OUT/tests"
}
compile_tests
"$OUT/tests" "$@"
