#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/PerformanceHUD-fan-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
# Compile native views too, so layout and menu checks exercise the real UI.
compile_tests() {
  set -- -swift-version 5 -parse-as-library
  for source in "$ROOT"/PerformanceHUD/*.swift; do
    case "$source" in
      */PerformanceHUDApp.swift|*/AppDelegate.swift) continue ;;
    esac
    set -- "$@" "$source"
  done
  xcrun swiftc "$@" "$ROOT"/PowerHelperShared/*.swift "$ROOT/Tests/FanTests.swift" -o "$OUT/tests"
}
compile_tests
"$OUT/tests" "$@"
