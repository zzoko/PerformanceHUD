# Compared with Apple's Metal performance HUD

[← Back to README](../README.md)

This isn't aimed at replacing MetalHUD — Apple's built-in tool is for deep graphics diagnostics and debugging. PerformanceHUD is a lighter, always-available layer on top of that: a system-resource overlay in the spirit of MSI Afterburner on Windows, not a rendering profiler.

### Advantages

- Toggles on anytime, mid-session — MetalHUD requires setting `MTL_HUD_ENABLED=1` before the game launches and can't be enabled for a session already in progress.
- Shows system context MetalHUD doesn't report at all: CPU, GPU, and RAM usage, temperatures, swap, memory pressure, and battery — MetalHUD is scoped to GPU rendering stats only.
- Fully yours to lay out — per-metric visibility, size, position, and keyboard shortcuts — versus MetalHUD's fixed overlay.
- A tiny, single-purpose app (~2 MB) rather than a debugging surface built into the graphics stack.

### Tradeoffs

- No frame-time graphs or detailed Metal rendering diagnostics — for that, MetalHUD is still the right tool.
- Most metrics refresh about once per second (battery and the glass background run on their own schedules); FPS specifically updates a bit slower than MetalHUD's.
- FPS and app GPU readings depend on what macOS exposes per game, so unsupported titles show blank readings — but compatibility tracks MetalHUD's own, covering most Crossover games, Steam games, Minecraft (Vulkan), and similar.
- Per-app readings cover the tracked process and may exclude helper processes, so values can differ from Activity Monitor.
- See [Display compatibility](../README.md#display-compatibility) for how this behaves in fullscreen.
- Adds its own sampling/rendering overhead — around 4% FPS impact in testing, varying by game and hardware.
