# Differences between PerformanceHUD and MetalHUD

[← Back to README](../README.md)

If you already use MetalHUD to watch your FPS, PerformanceHUD puts the rest of your Mac's activity beside it: CPU and GPU load, temperatures, power draw, memory pressure, fan speeds, and battery.

It's made to stay on screen while you play. Keep a few readings up for the whole session, or open a fuller view when you want to see how hard a game is pushing your Mac.

## What PerformanceHUD adds

- **The whole system, not just frames.** CPU, GPU and Neural Engine usage, temperatures and watts, down to per-core activity and clock speeds, plus memory pressure, swap, fans, battery charge rate, and readings for the app in focus. Useful context when tuning settings or comparing how demanding games are.
- **A layout that fits your setup.** A horizontal strip or a vertical panel, with the readings you pick and emphasis on the ones that matter. Size, position and appearance are adjustable, including Apple's native Liquid Glass with automatic Light/Dark switching.
- **Controls that work mid-game.** Show or hide the overlay with an editable hotkey, even after a game has launched. Other hotkeys start or stop logging and switch appearance, and focused-app readings follow whichever app is active.
- **Small details for everyday play.** A 60-second FPS history, automatic hiding when FPS goes away, presets for switching between setups, and a battery icon that reflects your Mac's power state.
- **CSV logging.** Record selected readings once per second, ready for a spreadsheet or graph.
- **Low overhead.** Native Liquid Glass rendering has shown under 1% performance overhead in current testing. Results vary by game, Mac and enabled readings.

## Where MetalHUD goes further

MetalHUD is built for diagnosing rendering: detailed frame timing, GPU rendering information, shader compilation statistics, and its own performance logging. For tracking down stutter or rendering bottlenecks, it's the right tool. PerformanceHUD's FPS history and CSV logs record sampled readings over time and don't replace per-frame Metal diagnostics. See [Apple's MetalHUD overview](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance).

MetalHUD's metrics, size, opacity and position can be customized too ([Apple's customization guide](https://developer.apple.com/documentation/xcode/customizing-metal-performance-hud)). What sets PerformanceHUD apart is having system readings, flexible layouts and in-game controls together.

## Things to know

- **Compatibility:** FPS and focused-app GPU readings depend on what macOS exposes for each app, so they may not appear everywhere MetalHUD does. Per-app readings cover the app's main process and can differ from Activity Monitor. See [Display compatibility](../README.md#display-compatibility) for fullscreen behavior.
- **Update rate:** Most readings update about once per second. FPS is sampled, not measured for every frame.
- **Setup:** PerformanceHUD is a separate app. Watt and clock-speed readings need the power helper; see [installation](INSTALL.md#downloaded-app) and [Privacy & access](PRIVACY_AND_ACCESS.md).
