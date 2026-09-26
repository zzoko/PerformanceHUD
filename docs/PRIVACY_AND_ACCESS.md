# Privacy & access

[← Back to README](../README.md)

FPS comes from Apple's macOS metalperftrace tool. CPU and app memory readings use macOS process statistics; GPU readings use IOKit GPU counters. System memory, swap, memory pressure, and battery readings come from macOS system statistics and power information. PerformanceHUD reads these measurements without modifying game files or injecting code into games.

Temperature estimates use read-only AppleSMC sensor readings, with the battery controller as a fallback for battery temperature. CPU, GPU, and Package power estimates use Apple’s `powermetrics` through a bundled, administrator-approved helper. These private interfaces and available sensors vary by hardware and macOS version; unavailable readings stay blank. Package power combines CPU, GPU, and Neural Engine readings and does not include the display or all other components of the Mac.

CPU and GPU Power are enabled by default, and first launch offers helper setup. Sampling runs only while the HUD and at least one visible CPU/GPU category’s Power option are enabled.

With an approved helper, Power checkboxes look normal while sampling is off. They are muted while requested readings start, then return to their normal appearance after the first valid sample. Declining setup, missing approval, removing the helper, or a persistent failure turns both options off and leaves them muted. They remain clickable while their category is enabled: click **Power** to open setup, repair, or approval settings. Successful setup or later approval enables both options again. Brief sampling gaps do not change your selections.

If macOS remembers approval but cannot start the helper, PerformanceHUD attempts to refresh its registration once before reporting failure. Setup, status, approval settings, and removal are available under **Power Helper**. Other metrics remain usable. Package uses CPU, GPU, and Neural Engine values from the same sample; missing or stale readings stay blank. See [installation and helper setup](INSTALL.md#enable-power-readings) for details.

ScreenCaptureKit is required to capture the area behind the HUD to display the transparent overlay on top, pixels are processed locally and captured frames stay in memory and are not saved as recordings or uploaded. This requires granting Screen Capture permission.
