#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/PerformanceHUD-hotkey-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
    "$ROOT/PerformanceHUD/HUDHotkeys.swift" \
    "$ROOT/PerformanceHUD/HUDHotkeyMonitor.swift" \
    "$ROOT/PerformanceHUD/HUDHotkeyEditor.swift" \
    "$ROOT/PerformanceHUD/HUDPanel.swift" \
    "$ROOT/PerformanceHUD/HUDPositionMenuView.swift" \
    "$ROOT/PerformanceHUD/HUDMenuLayout.swift" \
    "$ROOT/PerformanceHUD/HUDBackground.swift" \
    "$ROOT/Tests/HotkeyTests.swift" -o "$OUT/tests"
"$OUT/tests" "$@"
