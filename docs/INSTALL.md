# Installing PerformanceHUD

[← Back to README](https://github.com/zzoko/PerformanceHUD/blob/main/README.md)

Requires an Apple silicon Mac running macOS 27.0 or later. Choose the **Downloaded app** instructions below, or skip to **Build from source** if you are compiling it yourself.

<table>
<tr><td width="1000">

## Downloaded app

<details>
<summary><strong>Step-by-step setup</strong></summary>

### Allow the app to open

The ready-built app is not Developer ID–signed or notarized. macOS may block its first launch. Only approve a copy you obtained from the official PerformanceHUD download and trust.

1. Extract the ZIP and move **PerformanceHUD.app** into **Applications**.
2. Open that copy from Finder. If macOS says the developer cannot be verified or Apple cannot check the app, dismiss the alert without deleting the app.
3. Go to **System Settings → Privacy & Security**. In the Security section, find the message about PerformanceHUD and choose **Open Anyway**.
4. Confirm that you want to open it; authenticate if macOS asks. The exception is normally remembered for that copy.
5. Look for the **lightning-bolt icon in the menu bar** to access PerformanceHUD's controls.

This uses an exception for this app, not a system-wide change. Do not disable Gatekeeper or remove download security metadata to follow these instructions. If there is no approval option, or the message says the app is damaged or will damage your computer, stop and contact the seller/developer with the exact message. Managed Macs may prevent manual approval.

[Apple's guidance on opening downloaded apps](https://support.apple.com/en-us/102445)

### Allow Background App Activity

Background activity approval allows PerformanceHUD’s power helper to provide CPU, GPU, ANE, and SoC watt readings. On first launch, choose **Enable Power Readings** in the app’s prompt. If macOS requests approval, open **System Settings → General → Login Items & Extensions → Login Items** and turn on **PerformanceHUD** under **Background App Activity**. The path may vary slightly between macOS versions. Authenticate with Touch ID or an administrator password if asked. CPU, GPU, and ANE Power are enabled by default.

You can choose **Not Now** and continue using the other metrics. If setup is declined, approval is missing, the helper is removed, or it repeatedly fails to respond, Power checkboxes turn off and appear muted. They remain clickable while their category is enabled: click **Power** to open setup, repair, or approval settings. Successful setup or later approval enables these options again. Brief startup delays or missing samples do not change your selections. Use **Power Helper → Set Up Power Readings…** in the menu to enable watts later, or **Remove Power Helper** to unregister it. Sampling stops when no visible category needs Power, or when the HUD is disabled or the app is closed. The installed helper is otherwise idle.

CPU, GPU, ANE, and SoC watts all use this helper. ANE shows power only; utilization percentage, temperature, and focused-app usage are not offered. SoC Power is the combined CPU, GPU, and Neural Engine estimate, not whole-Mac power consumption. Its checkbox works independently of the individual Power options and is available in both Vertical and Horizontal alignment. Missing or unsupported readings stay blank.

An approved helper shows **Power helper idle** with normal-looking Power checkboxes when sampling is off. When sampling is requested, it shows **Starting power readings…** until its first valid sample arrives. If macOS remembers approval but cannot launch the helper, the app attempts to refresh that existing registration once. It does not bypass macOS approval.

If watts remain blank after setup, open **Power Helper** and check its status. Use **Open Approval Settings…** if approval is pending, **Update Power Helper…** if an update is needed, or **Repair Power Helper…** if setup needs to be repeated. Other metrics can still be used while power readings are unavailable.

### Allow Screen Recording

macOS calls this permission **Screen & System Audio Recording**. PerformanceHUD uses screen capture access to create the glass background from pixels behind the HUD; CPU, memory, and other statistics do not use those captured pixels. Frames are processed locally, not saved as recordings or uploaded. The app does not capture microphone or system audio.

- Follow the screen capture permission prompt. You can also open **Screen Recording Settings…** from the PerformanceHUD menu when permission is missing.
- In **System Settings → Privacy & Security → Screen & System Audio Recording**, allow PerformanceHUD. The label may vary slightly between macOS versions.
- If macOS requests a quit and reopen, do so. Otherwise, choose **Retry Background** from the app's menu if it remains available.
- A checkerboard means the background is waiting for a capture frame or capture is unavailable. Without permission, metrics can still appear over that fallback.

[Apple's screen recording permission guide](https://support.apple.com/guide/mac-help/mchld6aa7d23/mac)

### Updating or removing the app

Keep the app in a stable location, preferably Applications. To update, quit PerformanceHUD, replace that copy with the new version, then open it. If prompted, choose **Update Helper** so macOS uses the new bundled helper. Your HUD preferences are retained. Avoid running multiple copies at once.

Before deleting the app, choose **Power Helper → Remove Power Helper**, wait for removal to finish, then quit PerformanceHUD and move it to the Trash. Removing the helper alone leaves the app and its other metrics available.

</details>

<details>
<summary><strong>Watch the installation walkthrough</strong></summary>

Watch a quick walkthrough of installing the app and granting macOS permissions. These are normally remembered for later launches. When updating the app, you usually only need to approve the updated power helper if prompted. The exact prompts may vary.

[![Watch the PerformanceHUD installation walkthrough on YouTube](https://img.youtube.com/vi/7mou4dwnUpE/hqdefault.jpg)](https://youtu.be/7mou4dwnUpE)

</details>

</td></tr>
</table>

<table>
<tr><td width="1000">

## Build from source

<details>
<summary><strong>Build instructions</strong></summary>

1. Download or clone the official repository and read [LICENSE](../LICENSE). Personal builds and modifications are permitted; compiled redistribution is not.
2. Open **PerformanceHUD.xcodeproj** in an Xcode version that includes the macOS 27 SDK or newer.
3. Select each target, **PerformanceHUD** and **PowerHelper**, then **Signing & Capabilities**. Replace the author's saved development team with your own team and use matching Apple signing certificates for both. You do not need the author's signing credentials. Ad-hoc (unsigned/local-only) builds can use other metrics but cannot enable the power helper.
4. Select the **PerformanceHUD** scheme and **My Mac**, then choose **Product → Run**.
5. Follow **Allow Background App Activity** and **Allow Screen Recording** above for the optional glass background and watt readings.

A locally compiled app generally does not need the downloaded-app Gatekeeper exception. Screen capture permission is separate and can be requested again if the build's signing identity changes. Xcode is required to build the source, not to follow the downloaded-app installation steps.

### Developer checks

From the repository folder, run:

```sh
./Tests/run-power-helper-tests.sh
./Tests/run-fan-tests.sh
./Tests/run-appearance-tests.sh
./Tests/run-dynamic-fps-tests.sh
./Tests/run-dynamic-fps-glass-tests.sh
```

These checks cover sample parsing, stale or invalid readings, process restarts, stopping/resuming, and expired client connections. Fan checks cover decoding, missing and stopped fans, averaging, fanless defaults, menu availability, and stable layouts across fan counts, modes, and scales. Appearance checks cover saved choices, Follow system, and live Light/Dark changes. FPS checks cover saved modes, collapse timing, both layouts, animation recovery, and fixed capture geometry; glass checks exercise the Metal renderer during width and height transitions. They use simulated data, require no administrator approval, and do not register a helper. The test files are not included in the app. Real fan RPM, power readings, and macOS approval still need testing with an exported app on suitable physical hardware. The optional `--probe` argument to the fan tests also reads the local Mac’s fan sensors.

</details>

</td></tr>
</table>
