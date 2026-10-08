#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/PerformanceHUD-memory-pressure-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
    "$ROOT/PerformanceHUD/MetricPoller.swift" \
    "$ROOT/PerformanceHUD/MemoryPressureMonitor.swift" \
    "$ROOT/Tests/MemoryPressureMonitorTests.swift" -o "$OUT/tests"
"$OUT/tests"
