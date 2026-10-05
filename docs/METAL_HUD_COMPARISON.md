# Differences between PerformanceHUD and MetalHUD

[← Back to README](../README.md)

If you already use MetalHUD to keep an eye on FPS, PerformanceHUD brings more of your Mac’s activity into the same view: CPU and GPU usage, temperatures, power draw, memory pressure, fan speeds, and battery information.

It’s built around the experience of using an overlay while playing. Keep a few readings visible throughout a session, or open up a fuller view when you want to see how your Mac is handling a game.

## What PerformanceHUD adds

- **A wider view of your Mac.** See system usage alongside supported focused-app readings, plus CPU, GPU, and Neural Engine watts, temperatures, swap, memory pressure, fans, and battery state. These give you more context when adjusting settings or comparing how demanding different games are.
- **A layout that fits your setup.** Choose a horizontal strip or vertical layout, show individual readings, and highlight the values that matter most. Adjust the size, position, and appearance, including Apple’s native Liquid Glass effect and automatic Light/Dark switching.
- **Convenient controls while you play.** Turn the overlay on or off from the menu bar or with a keyboard shortcut, even after launching a game. Your choices stay saved as you move between apps, and supported focused-app readings follow the active app.
- **Small details for everyday use.** A 60-second FPS history, optional automatic hiding of the FPS area or the whole overlay when FPS becomes unavailable, individual or averaged fan readings, and a battery icon that reflects your Mac’s power state.
- **CSV logging for later comparison.** Record selected readings once per second from the menu bar, then use the saved CSV in a spreadsheet or graph. Unavailable readings stay blank, and logging continues while the HUD is automatically hidden.
- **Low performance overhead.** The new native Liquid Glass rendering removes continuous screen capture and custom glass processing, with **under 1% performance overhead observed in current testing**. Results vary by game, Mac, and enabled readings.

## Where MetalHUD goes further

MetalHUD provides detailed frame timing, GPU rendering information, shader compilation statistics, and performance logging. Those tools are useful for investigating stutter and rendering bottlenecks. PerformanceHUD’s FPS history and CSV logs record sampled readings over time; they do not replace per-frame timing or Metal rendering diagnostics. See [Apple’s MetalHUD overview](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance).

MetalHUD also supports changing its displayed metrics, size, opacity, and position. PerformanceHUD’s appeal is its combination of system readings, layouts, and everyday controls. See [Apple’s customization guide](https://developer.apple.com/documentation/xcode/customizing-metal-performance-hud).

## Things to know

- **Readings and compatibility:** FPS and focused-app GPU readings depend on what macOS exposes for each app. Unsupported readings stay blank; matching MetalHUD compatibility is not guaranteed. Per-app readings cover the tracked process and may exclude helper processes, so values can differ from Activity Monitor. See [Display compatibility](../README.md#display-compatibility) for fullscreen behavior.
- **Refresh rate:** Most metrics update about once per second; temperatures and battery information use different schedules. macOS renders the native glass independently. The FPS display is sampled, rather than updated for every frame.
- **Setup:** PerformanceHUD is a separate app. Watt readings need the approved power helper. Native Liquid Glass needs no screen recording permission. See [installation](INSTALL.md#downloaded-app) and [Privacy & access](PRIVACY_AND_ACCESS.md).
