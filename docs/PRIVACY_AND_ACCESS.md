# Privacy & access

[← Back to README](../README.md)

PerformanceHUD processes readings and screen pixels locally on your Mac. The app and its power helper contain no analytics, advertising, or network uploads. They do not send performance readings or captured screen content to the developer or any other service.

## What it reads

- **FPS:** Apple's macOS `metalperftrace` tool provides readings for the focused app. The FPS history is held in memory, not saved as a recording or log.
- **CPU, GPU, and memory:** macOS process and system statistics provide CPU and memory usage, swap, and memory pressure. GPU usage comes from IOKit counters. The app identifies the frontmost process for focused-app readings; those readings may exclude the app's helper processes.
- **Temperatures and fans:** Read-only AppleSMC access provides available temperature sensors, fan RPM, and maximum fan speeds. Battery temperature can fall back to the battery controller. Fan monitoring does not need the power helper and never changes fan speeds or cooling settings.
- **Battery and device information:** macOS power and system information provides charge, power source, power mode, chip name, and macOS version.
- **Power:** Apple's `powermetrics` provides estimated CPU, GPU, and Apple Neural Engine watts through the bundled power helper. SoC Power combines all three from the same sample; it is not the Mac's total power consumption and excludes the display and other components. ANE offers power only.

PerformanceHUD does not modify game files or inject code into games. Some readings rely on private interfaces or hardware-specific sensors, so availability varies by Mac, macOS version, and tracked app. Unsupported readings remain blank; fan detection failures are shown separately from “No fans detected.”

## Screen recording permission

All appearance modes—Clear, Light, Dark, and Follow system—use ScreenCaptureKit for the custom glass effect. macOS lists this permission under **Screen & System Audio Recording**, but PerformanceHUD captures neither system audio nor microphone audio.

The capture stream is cropped to the area around the HUD, including a small margin for the effect, and excludes PerformanceHUD itself. With Auto hide set to FPS or All options, the full expanded HUD area remains reserved for capture during collapse and reveal animations. In All options mode, glass capture stops once the whole HUD is hidden; FPS detection continues so the HUD can reappear when readings return. Captured pixels may include whatever other apps display in that area. Frames stay in memory and are not saved as screenshots, video recordings, or uploaded.

macOS may also ask to allow capture without its private window picker. PerformanceHUD selects the display behind the HUD directly and crops the capture to the area described above.

Screen capture supplies the glass effect, not the performance statistics. Without approval, metrics remain usable over a checkerboard fallback. You can revoke capture permission in System Settings; see [Apple’s screen recording permission guide](https://support.apple.com/guide/mac-help/mchld6aa7d23/mac).

## Power helper access

CPU, GPU, and ANE Power are enabled by default, and first launch offers helper setup. The helper runs with administrator privileges after macOS approval through **Background App Activity**. It runs a fixed `powermetrics` command; the app cannot send it arbitrary commands, file paths, or sampling arguments. App and helper connections are checked against their signing identities and matching developer team.

Power sampling runs only while the HUD is enabled and a visible power option needs readings. It also pauses once Auto hide → All options has fully hidden the HUD. SoC Power can request readings independently of the individual CPU, GPU, and ANE options. Otherwise, the installed helper is idle. Quitting the app stops sampling; normal system sleep remains allowed.

Brief gaps can retain the last valid power value for up to five seconds from its sample timestamp. Longer gaps clear it, as do stopping the HUD, sleep, or a helper disconnect. Other metrics remain usable if power setup is declined or unavailable.

Use **Power Helper** in the menu for status, setup, repair, or **Remove Power Helper** to unregister it. If macOS remembers approval but cannot start it, the app can attempt one registration refresh; this does not bypass approval. See the [installation guide](INSTALL.md#downloaded-app) for setup and removal steps.

## What is stored

HUD preferences and helper setup state are saved locally using macOS preferences. Live readings, FPS history, and captured frames are not written to a usage-history database or uploaded. Resetting display options does not revoke macOS permissions or remove the helper; those are managed separately as described above.
