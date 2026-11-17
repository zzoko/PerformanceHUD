# Privacy & access

[← Back to README](../README.md)

PerformanceHUD processes readings locally on your Mac. The app and its power helper contain no analytics or advertising. They do not send performance readings, CSV logs, game names, or screen content to the developer or any other service. Update checks use the network as described below; the power helper does not.

## App updates

PerformanceHUD makes one update check on first launch, even with **Automatic update checks → Off**. It offers a newer version if available and stays quiet if the app is current or the check cannot connect. This one-time check does not repeat after resetting HUD options or updating the app.

You can also choose **Check for updates** at any time or enable Weekly or Monthly checks. The recurring schedule is **Off** by default. Checks happen only while the app is running, including an overdue scheduled check after launch. All checks contact the PerformanceHUD update service hosted by Cloudflare over HTTPS. Downloads and restarts require your choice.

Cloudflare receives ordinary connection information such as your IP address, request time, and app/updater version information. Sparkle's optional system profiling is disabled, and there is no persistent installation identifier. Cloudflare may process service/security data and aggregate usage metrics.

Update information and downloaded app packages are cryptographically signed and verified. Update preferences and check/download state are stored locally.

## What it reads

- **FPS:** Apple's macOS `metalperftrace` tool provides readings for the focused app. The live FPS history is held in memory. Optional logging saves sampled FPS only when you start it.
- **CPU, GPU, and memory:** macOS process and system statistics provide CPU and memory usage, swap, and memory pressure. GPU usage comes from IOKit counters. The Vertical-only Process category identifies the frontmost process for focused-app readings; those readings may exclude the app's helper processes.
- **Temperatures and fans:** Read-only AppleSMC access provides available temperature sensors, fan RPM, and maximum fan speeds. Battery temperature can fall back to the battery controller. Fan monitoring does not need the power helper and never changes fan speeds or cooling settings.
- **Battery charge rate:** Read-only AppleSMC battery voltage and signed current provide net charging or discharging power, with macOS’s published battery-controller readings as a fallback. This does not need the power helper or change charging settings.
- **Battery and device information:** macOS power and system information provides charge, power source, power mode, chip name, and macOS version.
- **Power and frequency:** Apple's `powermetrics` provides estimated CPU, GPU, and Apple Neural Engine watts through the bundled power helper. SOC Combined power adds all three from the same sample; it is not the Mac's total power consumption and excludes the display and other components. The same fixed sampling command supplies CPU and GPU frequency. Per-core CPU usage bars use unprivileged tick counters and don't need the helper.
- **Optional Misc readings:** Metal output resolution comes from the FPS sampler; it can differ from a game's internal rendering resolution. Display refresh rate uses visible-window bounds and display metadata, without screen images or window titles. Game Mode uses a read-only, undocumented macOS status notification and remains experimental. Thermal state comes from macOS. Misc is available in Vertical only and is disabled by default.

PerformanceHUD does not modify game files or inject code into games. Some readings rely on private interfaces or hardware-specific sensors, so availability varies by Mac, macOS version, and tracked app.

## Liquid Glass and display notifications

While the HUD is visible, a display-refresh listener receives change notifications without reading screen pixels. It stops when the HUD is hidden, during sleep, and on shutdown. FPS detection continues while Auto hide → All hides the HUD, so it can reappear when readings return.

The listener addresses an observed game FPS cap with native glass. It relies on an older macOS interface that Apple no longer supports, so compatibility may change with system updates. If it cannot start, the glass still works and the menu offers **Retry Glass Compatibility**.

Older PerformanceHUD versions requested Screen Recording permission. This version does not use that permission; an existing entry may remain in System Settings.

## Power helper access

CPU, GPU, and ANE Power are enabled by default, and first launch offers helper setup. The helper runs with administrator privileges after macOS approval through **Background App Activity**. It runs a fixed `powermetrics` command; the app cannot send it arbitrary commands, file paths, or sampling arguments. App and helper connections are checked against their signing identities and matching developer team.

Power sampling runs only while visible HUD readings, expanded menu-bar readings, or active logging need it; otherwise the installed helper is idle. Menu-bar readings can keep sampling while the HUD is disabled or automatically hidden, until they're collapsed. Quitting the app stops sampling, and normal system sleep remains allowed. Battery Charge watts use separate read-only sensors and do not need this helper.

Use **Power Helper** in the menu for status, setup, repair, or **Remove Power Helper** to unregister it. If macOS remembers approval but cannot start it, the app can attempt one registration refresh; this does not bypass approval. See the [installation guide](INSTALL.md#downloaded-app) for setup and removal steps.

## What is stored

**Auto start on login** is off by default. Choosing On registers PerformanceHUD with macOS Login Items; choosing Off removes that registration. This is separate from power helper approval. Resetting HUD options preserves the login setting, which can also be managed in System Settings.

HUD preferences, custom hotkeys, and helper setup state are saved locally using macOS preferences. Hotkeys register specific combinations with macOS; they do not monitor general typing or require Accessibility or Input Monitoring permission. Readings are not saved unless you start logging; no readings are uploaded. Resetting display options does not revoke macOS permissions or remove the helper; those are managed separately as described above.

## Optional CSV logging

**Start logging** records selected HUD readings and timestamps locally, once per second, for use in spreadsheets and graphs. App readings follow the focused process. Process names are included only when **Process** is enabled in Vertical when logging starts; process IDs are not included.

**Stop logging**, disabling the HUD, or quitting saves the CSV to your Desktop. Auto hide does not stop logging. macOS may request Desktop folder access to save the file. Logging never starts automatically.

During recording, the app writes a recovery CSV under `~/Library/Application Support/PerformanceHUD/Logs/`. That copy is removed after a successful Desktop save. If saving fails or the app exits unexpectedly, the recovery file stays there; a save-error alert offers to show it in Finder. You can delete CSV and recovery files whenever you no longer need them. The files contain no screen images or audio.
