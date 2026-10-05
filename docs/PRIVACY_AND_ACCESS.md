# Privacy & access

[← Back to README](../README.md)

PerformanceHUD processes readings locally on your Mac. The app and its power helper contain no analytics, advertising, or network uploads. They do not send performance readings or screen content to the developer or any other service.

## What it reads

- **FPS:** Apple's macOS `metalperftrace` tool provides readings for the focused app. The live FPS history is held in memory. Optional logging saves sampled FPS only when you start it.
- **CPU, GPU, and memory:** macOS process and system statistics provide CPU and memory usage, swap, and memory pressure. GPU usage comes from IOKit counters. The app identifies the frontmost process for focused-app readings; those readings may exclude the app's helper processes.
- **Temperatures and fans:** Read-only AppleSMC access provides available temperature sensors, fan RPM, and maximum fan speeds. Battery temperature can fall back to the battery controller. Fan monitoring does not need the power helper and never changes fan speeds or cooling settings.
- **Battery and device information:** macOS power and system information provides charge, power source, power mode, chip name, and macOS version.
- **Power:** Apple's `powermetrics` provides estimated CPU, GPU, and Apple Neural Engine watts through the bundled power helper. SoC Power combines all three from the same sample; it is not the Mac's total power consumption and excludes the display and other components. ANE offers power only.

PerformanceHUD does not modify game files or inject code into games. Some readings rely on private interfaces or hardware-specific sensors, so availability varies by Mac, macOS version, and tracked app. Unsupported readings remain blank; fan detection failures are shown separately from “No fans detected.”

## Liquid Glass and display notifications

Light, Dark, and Follow system use Apple’s native Liquid Glass. This version does not use ScreenCaptureKit, request Screen Recording permission, read screen pixels, or capture microphone/system audio. macOS renders the effect directly; PerformanceHUD does not hold or save background frames.

While the HUD is visible, a legacy CoreGraphics screen-refresh listener receives change notifications. Its callback only counts notifications; it does not read the supplied rectangles or any image data. The listener is removed when the HUD is hidden, during sleep, and on shutdown. FPS detection continues while Auto hide → All options hides the HUD, so it can reappear when readings return.

The listener is a compatibility workaround for an observed game FPS cap with native glass. Apple marks this old API unsupported, and its effect on game composition is not guaranteed. If registration fails, the glass still works and the menu offers **Retry Glass Compatibility**. A separate own-window capture alternative is kept as disabled source in the repository; it is not compiled or included in this app.

Older PerformanceHUD versions requested Screen Recording permission. This version does not use that permission; an existing entry may remain in System Settings.

## Power helper access

CPU, GPU, and ANE Power are enabled by default, and first launch offers helper setup. The helper runs with administrator privileges after macOS approval through **Background App Activity**. It runs a fixed `powermetrics` command; the app cannot send it arbitrary commands, file paths, or sampling arguments. App and helper connections are checked against their signing identities and matching developer team.

Power sampling runs only while the HUD is enabled and a visible power option needs readings. It also pauses once Auto hide → All options has fully hidden the HUD, unless you have started logging. Logging keeps selected monitors running while automatically hidden. SoC Power can request readings independently of the individual CPU, GPU, and ANE options. Otherwise, the installed helper is idle. Quitting the app stops sampling; normal system sleep remains allowed.

Brief gaps can retain the last valid power value for up to five seconds from its sample timestamp. Longer gaps clear it, as do stopping the HUD, sleep, or a helper disconnect. Other metrics remain usable if power setup is declined or unavailable.

Use **Power Helper** in the menu for status, setup, repair, or **Remove Power Helper** to unregister it. If macOS remembers approval but cannot start it, the app can attempt one registration refresh; this does not bypass approval. See the [installation guide](INSTALL.md#downloaded-app) for setup and removal steps.

## What is stored

HUD preferences and helper setup state are saved locally using macOS preferences. Readings are not saved unless you start logging; no readings are uploaded. Resetting display options does not revoke macOS permissions or remove the helper; those are managed separately as described above.

## Optional CSV logging

**Start logging** records selected HUD readings and timestamps locally, once per second, for use in spreadsheets and graphs. Columns follow the menu order and use the selections at the start of the session. Unavailable or subsequently disabled readings are blank; newly selected columns require a new log. App readings follow the focused process, but process names and IDs are not included.

**Stop logging**, disabling the HUD, or quitting saves the CSV to your Desktop. Auto hide does not stop logging. macOS may request Desktop folder access to save the file. Logging never starts automatically.

During recording, the app writes a recovery CSV under `~/Library/Application Support/PerformanceHUD/Logs/`. That copy is removed after a successful Desktop save. If saving fails or the app exits unexpectedly, the recovery file stays there; a save-error alert offers to show it in Finder. You can delete CSV and recovery files whenever you no longer need them. The files contain no screen images or audio.
