# PerformanceHUD

## ↓ Download options

➤ Source is available to build and modify for personal use under the [personal-use license](LICENSE). You can build it yourself for free using the [installation instructions](INSTALL.md).

➤ <img src="https://cdn3.emoji.gg/emojis/24562-kofi.png" width="20" height="20" alt="Ko-fi"> **[Download on Ko-fi](https://ko-fi.com/s/01a23ddc51)** — Get the ready-built app for a one-time $3.99 to support me and the development time that has gone into it. It offers the same features as the version you build yourself. No subscription or feature unlocks.

**➤ GitHub sponsorships** — If you prefer to build the app yourself but would still like to support it, direct GitHub sponsorships will offer another way to contribute. A link will be added once approved.

## Showcase

Watch PerformanceHUD used:
[Gameplay video 1](https://youtu.be/ZI6cvaOitAE?si=BmEyrPy4rH7b7GAM)

## What is this?

PerformanceHUD is a macOS menu-bar app that keeps useful performance information visible over your game or app. Values shown are customizable and can be toggled on and off, and the HUD can be repositioned and resized on screen.

<img src="docs/images/HUD_desktop_transparent.png" alt="PerformanceHUD on the desktop with a transparent background, resource usage, temperatures, memory details, and battery status" width="260">

- FPS for supported apps and games, and FPS history graph showing trends over the last 60 seconds.
- GPU, CPU, and RAM usage for the focused app or the whole system.
- Estimated CPU and GPU temperatures and power consumption on supported hardware, plus a combined CPU, GPU, and Neural Engine power estimate.
- Battery percentage, power source, and estimated battery temperature on supported MacBooks.
- Device information such as chip name and macOS version.


## Compared with Apple's Metal performance HUD

This is not aimed to be a MetalHUD replacement, Apple's built-in Metal HUD focuses on deep graphics diagnostics and debugging. PerformanceHUD focuses on showing a simpler overview of used system resources, similar to MSI Afterburner overlays on Windows.

### Advantages

- Tiny, purpose-built app without unnecessary extras or bundled bloatware—approximately 2.18 MB for the app, including the power-reading helper.
- Can be enabled any time without re-opening the game.
- App and system resource readings alongside FPS, plus swap, memory pressure, and battery.
- Configurable layout with individual metric toggles, adjustable size, position and keyboard shortcuts.
- HUD resolution stays rendered at sharp retina resolution even if the game is set to a low resolution.

<img src="docs/images/HUD_menu_settings.png" alt="PerformanceHUD menu with size, position, background, and individual metric controls" width="640">

### Tradeoffs

- No frame-time graphs or detailed Metal rendering diagnostics.
- Most metrics refresh approximately once per second. Battery updates less frequently, and the glass background refreshes independently. In practice the notable downside is that FPS is limited to updating slightly slower than metalHUD.
- FPS and app GPU readings depend on the game and the counters macOS exposes; unsupported readings remain blank. It should however work for any game that metalHUD also can, such as most Crossover games, Steam games, Minecraft (using Vulkan render), etc.
- Per-app readings cover the tracked process and may exclude helper processes. Values can differ from Activity Monitor.
- Designed for borderless and windowed games. Exclusive fullscreen support is unlikely to work for most game although some may still work; expect the HUD not to appear in that mode as it cannot render on top.
- Sampling, calculating and rendering data add performance overhead. In my testing, enabling PerformanceHUD in-game reduced FPS by around 4%. The actual exact impact will vary by game, hardware, and settings.

## Changelog

### v1.1

- Reworked the HUD UI with refined spacing, slightly stronger main labels, and neatly aligned readings grouped on the right. The rightmost enabled reading uses the larger number style, including when only power or temperature is shown.
- Improved the FPS history graph with a smoother, slightly bolder line, more visible FPS variations, and a translucent gradient fill that fades down to the divider.
- Added a more compact HUD width when FPS is the only enabled category.
- Added estimated battery temperature for supported MacBooks, alongside a small “Power source” heading and the Battery / Power Adapter label. Battery Temperature and Energy can be toggled separately and are enabled by default.
- Added estimated CPU and GPU power consumption in watts, shown to one decimal place. A Package row shows the combined CPU, GPU, and Neural Engine power estimate when both CPU and GPU power readings are enabled and visible. Power is enabled by default for both; the Package estimate does not represent whole-Mac power consumption.
- Added first-launch setup and menu controls for the optional power-reading helper, shared by CPU, GPU, and Package watts.
- Improved the menu with Power options for CPU and GPU, grouped battery controls, and more consistent alignment. Position now appears above Size.
- Replaced the size buttons with a rounded fill slider covering 0.75× to 1.25× in 0.05× steps, with live resizing and 1× as the default.

### v1.0

- Initial release.

## Future ideas — under consideration

These are potential additions, not planned or guaranteed features:

- Fan speed (RPM), on Macs with fans.

## Technical details on what it accesses

FPS comes from Apple's macOS metalperftrace tool. CPU and app memory readings use macOS process statistics; GPU readings use IOKit GPU counters. System memory, swap, memory pressure, and battery readings come from macOS system statistics and power information. PerformanceHUD reads these measurements without modifying game files or injecting code into games.

Temperature estimates use read-only AppleSMC sensor readings, with the battery controller as a fallback for battery temperature. CPU, GPU, and Package power estimates use Apple’s `powermetrics` through a bundled, administrator-approved helper. These private interfaces and available sensors vary by hardware and macOS version; unavailable readings stay blank. Package power combines CPU, GPU, and Neural Engine readings and does not include the display or all other components of the Mac.

CPU and GPU Power are enabled by default, and first launch offers helper setup. Sampling runs only while the HUD and at least one visible CPU/GPU category’s Power option are enabled.

With an approved helper, Power checkboxes look normal while sampling is off. They are muted while requested readings start, then return to their normal appearance after the first valid sample. Declining setup, missing approval, removing the helper, or a persistent failure turns both options off and leaves them muted. They remain clickable while their category is enabled: click **Power** to open setup, repair, or approval settings. Successful setup or later approval enables both options again. Brief sampling gaps do not change your selections.

If macOS remembers approval but cannot start the helper, PerformanceHUD attempts to refresh its registration once before reporting failure. Setup, status, approval settings, and removal are available under **Power Helper**. Other metrics remain usable. Package uses CPU, GPU, and Neural Engine values from the same sample; missing or stale readings stay blank. See [installation and helper setup](INSTALL.md#enable-power-readings) for details.

ScreenCaptureKit is required to capture the area behind the HUD to display the transparent overlay on top, pixels are processed locally and captured frames stay in memory and are not saved as recordings or uploaded. This requires granting Screen Capture permission.

## Requirements

- Apple silicon Mac (M-series), running macOS 27.0 or later.
- Screen Capture permission for the glass background.
- Administrator approval for the optional power-reading helper.

Metal HUD reference: [Apple Metal developer tools](https://developer.apple.com/metal/tools/).

## License

Source available for private, personal, non-commercial use. You may build and modify the app for yourself. Redistribution of compiled copies, whether free or paid, and resale are prohibited without prior written permission. The official paid download has the same personal-use restrictions. See [LICENSE](LICENSE) for the full terms.
