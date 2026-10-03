#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/PerformanceHUD-glass-transition-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
cat "$ROOT/PerformanceHUD/PerformanceHUDGlassBackground.swift" "$ROOT/Tests/GlassTransitionTests.swift" > "$OUT/GlassTests.swift"
compile_tests() {
  set -- -swift-version 5 -parse-as-library
  for source in "$ROOT"/PerformanceHUD/*.swift; do
    case "$source" in
      */PerformanceHUDApp.swift|*/AppDelegate.swift|*/PerformanceHUDGlassBackground.swift) continue ;;
    esac
    set -- "$@" "$source"
  done
  xcrun swiftc "$@" "$ROOT"/PowerHelperShared/*.swift "$OUT/GlassTests.swift" -o "$OUT/tests"
}
compile_tests
"$OUT/tests" "$@"
