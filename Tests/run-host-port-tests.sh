#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/PerformanceHUD-host-port-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
    "$ROOT/PerformanceHUD/MetricPoller.swift" \
    "$ROOT/PerformanceHUD/TotalCPUUsageMonitor.swift" \
    "$ROOT/PerformanceHUD/TotalRAMUsageMonitor.swift" \
    "$ROOT/PerformanceHUD/RAMUsageSample.swift" \
    "$ROOT/Tests/HostPortTests.swift" -o "$OUT/tests"
"$OUT/tests"
