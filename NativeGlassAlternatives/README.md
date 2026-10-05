# Native glass implementations

**Active: Method 67** in `PerformanceHUD/NativeGlassSession.swift`. It registers a legacy CoreGraphics screen-refresh callback while the HUD is visible. The callback reads no pixels. Apple deprecated this API as unsupported; its observed effect on game composition/FPS is not guaranteed. Registration success is not an FPS measurement.

**Disabled: Method 68** in `Alternative_Method68/NativeGlassSession.swift`, preserved exactly as supplied. This folder is an Xcode reference, outside the app’s synchronized source folder, with no target membership and no Copy Resources entry. It is neither compiled nor bundled. There is no automatic fallback.

Both use `PerformanceHUD/NativeGlassHUDBackground.swift`: regular NSGlassEffectView, no tint or interactive effect, a 16 pt radius at 1× and the supplied Soft v2 exterior shadow. The HUD scales the radius with its size; the 24 pt shadow padding is applied only once. Content is a transparent sibling above the glass, with separate clipping during collapse. The actual window follows the animated body size.

## Switching later

1. Back up the active session before replacing it. Compile exactly one NativeGlassSession implementation.
2. Method 68 uses ScreenCaptureKit to capture this process’s own HUD window at 2 × 2, then requests one frame per hour. It is still capture; it may display macOS’s capture indicator. Never fall back to capturing a display or other apps.
3. Adapt its status/failure updates to the controller’s `onStateChange` / `failure` interface. Keep retries bounded. Method 67 currently stops synchronously; Method 68 requires awaiting its asynchronous shutdown, including AppDelegate’s termination path, before closing the app.
4. Retain the visibility contract: start after orderFront; stop before orderOut. Check sleep/wake, screen changes, Auto hide, disabled/empty HUDs, retries, close and quit. Keep one session per window across layout and appearance changes.
5. Update privacy, installation and Controls Guide text to describe whichever method actually ships. Repeat gameplay tests for the FPS cap and capture-indicator behavior; neither method’s registration/stream status proves a game is uncapped.

The supplied integration notes are retained alongside this file. They describe the standalone package; the host-specific lifecycle and status adaptations above must also be applied before enabling Method 68.

## Verification references

- [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)
- [Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/)
- [Legacy screen-refresh callback](https://developer.apple.com/documentation/coregraphics/cgregisterscreenrefreshcallback(_:_:))

Checked against the installed macOS 27 SDK: regular/clear glass styles, cornerRadius, tintColor and effectIsInteractive match the supplied code; CGRemoteOperation.h marks the refresh registration API “No longer supported” since macOS 10.8. There is no Apple-documented uncapping guarantee.
