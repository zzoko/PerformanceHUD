# Installing PerformanceHUD

Requires an Apple silicon Mac running macOS 27.0 or later. Choose the downloaded app instructions below, or skip to **Build from source** if you are compiling it yourself.

## Downloaded app

The initial ready-built release is not Developer ID–signed or notarized. macOS may block its first launch. Only approve a copy you obtained from the official PerformanceHUD download and trust.

1. Extract the ZIP and move **PerformanceHUD.app** into **Applications**.
2. Open that copy from Finder. If macOS says the developer cannot be verified or Apple cannot check the app, dismiss the alert without deleting the app.
3. Go to **System Settings → Privacy & Security**. In the Security section, find the message about PerformanceHUD and choose **Open Anyway**.
4. Confirm that you want to open it; authenticate if macOS asks. The exception is normally remembered for that copy.
5. Look for the **lightning-bolt icon in the menu bar** to access PerformanceHUD's controls.

This uses an exception for this app, not a system-wide change. Do not disable Gatekeeper or remove download security metadata to follow these instructions. If there is no approval option, or the message says the app is damaged or will damage your computer, stop and contact the seller/developer with the exact message. Managed Macs may prevent manual approval.

[Apple's guidance on opening downloaded apps](https://support.apple.com/en-us/102445)

## Enable the glass background

The glass effect uses ScreenCaptureKit to process pixels behind the HUD. It needs screen capture access; the CPU, RAM, and other statistics do not use those captured pixels. Frames are processed locally, not saved as recordings or uploaded. The app does not capture microphone or system audio.

- Follow the screen capture permission prompt. You can also open **Screen Recording Settings…** from the PerformanceHUD menu when permission is missing.
- In **System Settings → Privacy & Security → Screen & System Audio Recording**, allow PerformanceHUD. The label may vary slightly between macOS versions.
- If macOS requests a quit and reopen, do so. Otherwise, choose **Retry Background** from the app's menu if it remains available.
- A checkerboard means the background is waiting for a capture frame or capture is unavailable. Without permission, metrics can still appear over that fallback.

[Apple's screen recording permission guide](https://support.apple.com/guide/mac-help/mchld6aa7d23/mac)

## Build from source

1. Download or clone the official repository and read [LICENSE](LICENSE). Personal builds and modifications are permitted; compiled redistribution is not.
2. Open **PerformanceHUD.xcodeproj** in an Xcode version that includes the macOS 27 SDK or newer.
3. Select the **PerformanceHUD** target, then **Signing & Capabilities**. Replace the author's saved development team with your own team/local signing configuration. You do not need the author's signing credentials.
4. Select the **PerformanceHUD** scheme and **My Mac**, then choose **Product → Run**.
5. Grant screen capture permission using the section above if you want the trapsnaprent glass background.

A locally compiled app generally does not need the downloaded-app Gatekeeper exception. Screen capture permission is separate and can be requested again if the build's signing identity changes. Xcode is required to build the source, not to follow the downloaded-app installation steps.

## Quick controls

- **Control + Option + Command + H:** show or hide the HUD.
- **Control + Option + Command + drag:** move it. Release all three keys when finished to prevent automatic snapping to the grid.
- **Position → Reset:** return to the default position.
- **Close App:** quit PerformanceHUD.
- The faint **App version** line identifies the installed version.

FPS depends on the active game's rendering backend and available counters. An empty FPS value alone does not mean installation failed. Borderless or windowed mode is the recommended starting point for testing.
