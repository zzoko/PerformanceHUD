#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/PerformanceHUD-power-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$ROOT/PowerHelperShared/PowerHelperProtocol.swift" \
  "$ROOT/PowerHelper/PowerSampler.swift" \
  "$ROOT/PerformanceHUD/PowerHelperState.swift" \
  "$ROOT/Tests/PowerHelperTests.swift" -o "$OUT/tests"
"$OUT/tests"
