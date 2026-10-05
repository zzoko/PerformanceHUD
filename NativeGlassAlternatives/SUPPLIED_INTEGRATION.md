# Apple regular glass · Soft v2 · PerformanceHUD migration

Exported 5 October 2026 from the approved GlassTest visuals. This package is for
replacing **custom Light v2 and custom Dark** with Apple's native regular Liquid
Glass. It does not modify PerformanceHUD or the running GlassTest tester.

## Files to add

Add these **two root files** to the PerformanceHUD app target:

| File | Responsibility |
| --- | --- |
| `NativeGlassHUDBackground.swift` | Regular glass, native light/dark appearance, outside-only Soft v2 shadow, transparent content container. |
| `NativeGlassSession.swift` | Method **67**, the primary compositing workaround. No ScreenCaptureKit dependency. |

`Alternative_Method68/NativeGlassSession.swift` is a **replacement for the second
file**, not an extra dependency. Keep that folder outside the app target. Do not
drag the whole package into an automatically synchronized source folder. Both
session files deliberately define `NativeGlassSession`; only one may compile or
run. There is no method selector and no automatic fallback.

Requires macOS 26 or newer for `NSGlassEffectView`. The development machine/test
environment is macOS 27.x on M5; actual uncapping behavior is an observation from
that environment, not a guarantee for all supported deployment targets. These
files use Xcode's current Swift compiler and also support the main-actor default
isolation setting used by this PerformanceHUD project. No package or asset is needed.

This is a new integration, not a drop-in API replacement for
`PerformanceHUDGlassBackground` or the earlier combined `NativeGlassHUD.swift`.
Remove any earlier combined native export from target membership to avoid duplicate types.

## Exact visual recipe

| Setting | Light | Dark |
| --- | --- | --- |
| Native material | `NSGlassEffectView.style = .regular` | Same |
| Appearance | `.aqua` | `.darkAqua` |
| Custom glass tint/opacity | None; `tintColor = nil` | Same |
| Corner radius | 16 points by default | Same |
| Soft v2 shadow color | Black | Black |
| Soft v2 shadow opacity | 0.17 | 0.32 |
| Shadow radius / offset | 6 points / `(0, -2)` | Same |
| Transparent outer padding | 24 points per edge | Same |
| `NSWindow.hasShadow` | **false** | **false** |

Light and dark are Apple's appearances of the same regular material. There are
no separate custom color formulas, shaders, gradients, noise textures, or captured
backdrop images. macOS supplies the live blur and glass rendering. Interactive
feedback is disabled on macOS 27; this does not freeze the live background.

**Soft v2 is custom Core Animation shadow only.** A sibling layer draws the known
rounded shadow path. An even-odd mask removes its entire interior, leaving only
the shadow outside the glass. The mask is never applied to the glass or text.
It uses the approved Soft test 2 settings, not the old Soft shadow and not the
native window shadow. No extra border is drawn; Apple's own glass edge remains.

Text, graphs, separators, font sizes, metric layout, dragging, and shortcuts stay
owned by PerformanceHUD. The export does not include sample values or GT menus.

## Basic AppKit wiring

Own one background and one session strongly in the existing HUD controller.
All calls below run on the main actor. `metricsView` is your existing transparent
AppKit metrics container (or `NSHostingView`), with its existing inner text padding.

```swift
// Stored properties in your existing HUD controller:
private var nativeBackground: NativeGlassHUDBackground?
private var nativeSession: NativeGlassSession?

func installNativeGlass(in window: NSWindow, metricsView: NSView,
                        bodySize: NSSize, isDark: Bool) {
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false

    // bodySize is the visible glass area, not the padded window size.
    let outerSize = NativeGlassHUDBackground.sizeIncludingShadow(bodySize: bodySize)
    let background = NativeGlassHUDBackground(
        frame: NSRect(origin: .zero, size: outerSize)
    )
    background.isDark = isDark
    background.autoresizingMask = [.width, .height]

    window.setContentSize(outerSize)
    window.contentView = background
    background.layoutSubtreeIfNeeded()
    metricsView.frame = background.contentView.bounds
    metricsView.autoresizingMask = [.width, .height]
    background.contentView.addSubview(metricsView)

    nativeBackground = background
    nativeSession = NativeGlassSession(window: window)
    window.orderFrontRegardless()
    nativeSession?.setVisible(true) // AFTER the window is shown.
}

func setNativeDark(_ dark: Bool) {
    nativeBackground?.isDark = dark
    // Update your existing label/divider palette here if it uses fixed colors.
}

func hideNativeHUD(_ window: NSWindow) {
    nativeSession?.setVisible(false) // BEFORE every hide/orderOut path.
    window.orderOut(nil)
}

func showNativeHUD(_ window: NSWindow) {
    window.orderFrontRegardless()
    nativeSession?.setVisible(true)
}
```

Treat installation as one-time setup for that window. Before reinstalling or
replacing the window, stop and release the previous session; for 68, await shutdown
first. Keep your current nonactivating panel, window level, all-spaces/fullscreen
behavior, saved placement, and modifier-drag behavior. Window level alone was not
the successful workaround.

The `contentView` above is the export's transparent sibling **above** the glass,
not `NSGlassEffectView.contentView`. This keeps existing metrics independent of
the material. Ensure the metrics container itself has no opaque backing, extra
material, shadow, or full-panel fill hiding the glass.

## Geometry and existing layout

This export's frame includes the shadow padding. A 160 × 160 body therefore uses
a **208 × 208** content/window area. `background.bodyFrame` locates the visible
body; `background.contentView.bounds` is body-local coordinates starting at zero.

Do not apply the existing 24-point outer shadow inset again. Either use the export
as the padded root as above, or mount it over the entire existing padded root and
use its body/content coordinates. Keep clipping disabled on enclosing shadow
containers. Do not apply `.clipShape`, a root `cornerRadius` mask, or an extra
SwiftUI `.shadow` to the whole exported view.

When HUD content size changes, set the window/root to
`sizeIncludingShadow(bodySize:)` and let AppKit layout update the glass, cutout,
and shadow path. Preserve whichever screen edge your existing positioning code
anchors. `cornerRadius` is adjustable if the production HUD uses a scaled radius;
16 points matches the approved tester. Shadow radius/offset/padding stay in points.
Backing-scale changes update the shadow layers' scale automatically.

No source rectangle, capture resolution, frame-rate setting, or capture refresh
is needed for these visuals. Do not restart the session for each metric update,
theme change, ordinary resize, or movement on the same display. Display changes
are already observed by the session. Keep the session even if you replace only
the visual view in the same window.

## Replace the old custom Light v2 / Dark path

The inspected project currently connects the old renderer through `HUDWindowController.swift`
and `PerformanceHUDGlassBackground.swift`, with capture status UI in
`AppDelegate.swift` and reveal coordination in `HUDGlassRevealGate.swift`.
Use these as integration points; this export has not edited them.

1. Map existing Light to `isDark = false`, Dark to `true`. Resolve Follow system
   using the existing preference logic. Both use **regular** material. Custom
   Transparent/Clear is not automatically replaced by this export.
2. Stop the active old `PerformanceHUDGlassBackground` before switching; remove it
   from the view hierarchy and release it once its queued capture teardown has
   finished. A clean relaunch after migrating target membership is the simplest
   way to ensure no old maximum-rate capture remains. Merely covering or hiding
   the old view leaves its work running.
3. Replace the custom background factory/cast and old `.start()`, `.stop()`, and
   `.refreshGeometry()` call sites for the native branch with the visual layout
   and session lifecycle above. `setVisible(false)` also belongs on auto-hide,
   global shortcut, menu hide, and background-Off paths—even if the window is kept
   alive. If the host uses only `alphaValue = 0`, `NSApp.hide`, or `isHidden`, signal
   the session explicitly; there is no universal AppKit hide notification.
4. Bypass screen-recording permission checks, crop/reconfigure work, first-captured-
   frame readiness gates, and capture-reveal waits **for this native branch**.
   Native glass has no captured frame to wait for. Adapt collapse/expand layout to
   the native body's size, rather than retaining a larger captured footprint.
   Keep any unrelated auto-hide/reveal animation behavior.
5. Route native helper errors through `status`/`isActive`, not the old
   `HUDGlassCaptureState.permissionRequired` handling. A failed 67 registration is
   not a reason to open Screen Recording settings. The glass can still draw while
   the workaround is inactive; the FPS cap may return.
6. Remove the old maximum-rate SCStream, Metal blur/refraction renderer, cached
   CGImage backing, crop calculations, and old shadow from the Light/Dark path.
   If custom Transparent or another feature still needs those types, keep them
   isolated and inactive while native Light/Dark is selected. Preserve shared text
   colors/layout types until their remaining uses are accounted for.

The new native background does not provide the old `glassAppearance` text palette.
Keep your established text colors or use semantic label colors under the selected
appearance. Do not reapply the old light tint, dark tint, fill opacity, or shadow to
the native view. Keep the existing global shortcut; it should call the same host
show/hide functions rather than creating a second shortcut registration.

## Method 67 — primary

67 registers `CGRegisterScreenRefreshCallback` and unregisters it when no longer
needed. The callback receives changed-region metadata, not image buffers. This
implementation only counts callback deliveries; it does not read pixels, redraw
the HUD, create a stream, record a file, inject into a game, or run a polling timer.
The app must have its normal AppKit event loop running. Apple's callback contract
is described in the [CoreGraphics reference](https://developer.apple.com/documentation/coregraphics/cgregisterscreenrefreshcallback(_:_:)).

In the user's tests, 67 changed the Metal HUD report to **Composited**, preserved
live native blur, and removed the fixed 60 FPS cap. This is a discovered side
effect of the registration, **not an Apple-supported force-composition setting**.
The callback count and `isActive` cannot confirm another app's presentation mode
or FPS. There can still be composition overhead; 67/68 measured close to each other
in the user's comparisons, not a universal zero-cost result.

The SDK marks these legacy entry points deprecated since macOS 10.8 and
"No longer supported" (`CoreGraphics/CGRemoteOperation.h`). The helper resolves
both symbols dynamically and checks registration success. Missing symbols or an
error leave it stopped with an explanatory status. It never starts 68 secretly.
Compatibility after OS updates and distribution suitability are not established
by the local test. The native material API itself is separate from this legacy workaround.

The primary helper performs no screen-recording permission request/check and no
pixel capture. No recording UI was observed for 67 during testing. Do not add a
ScreenCaptureKit stream to the primary path as an extra precaution.

## Method 68 — separate replacement

If 67 ceases to work, remove the root `NativeGlassSession.swift` from the target
and add **only** `Alternative_Method68/NativeGlassSession.swift` instead. Leave
`NativeGlassHUDBackground.swift` unchanged. The shared interface is:

```swift
NativeGlassSession(window: window)
session.setVisible(true)   // after showing
session.setVisible(false)  // before hiding
session.retry()           // explicit retry after a reported failure
await session.shutdown()  // await completion before final release
session.status
session.isActive
```

68 uses `SCShareableContent.currentProcess` to find **this exact HUD window**, by
window ID and owning PID. It starts a **2 × 2 pixel output** at a requested one-second
minimum interval, then requests a **3,600-second minimum interval** after the first
complete frame. It retains the stream while visible. This is not the old display
capture, and 2 × 2 describes output dimensions, not proof that WindowServer only
processes four source pixels.

It discards pixel content; only delivered dimensions/counts/timestamps are inspected.
The glass still updates live through AppKit and does not use these frames. No
screen/game capture, audio, microphone, cursor, encoding, or file recording is
added. There is no full-display fallback if the own-window lookup fails.

Apple's SDK documents `currentProcess` as returning content available to the
current process without TCC consent (`ScreenCaptureKit/SCShareableContent.h`; see
the [API](https://developer.apple.com/documentation/screencapturekit/scshareablecontent/getcurrentprocessshareablecontent(completionhandler:))).
The earlier clean-identity test started it without an existing recording grant.
The user nevertheless observed a **capture menu-bar item** with 68, without the
blue privacy dot. It remains an active capture session. Do not describe it as
capture-free, stopped, or guaranteed free of permission/UI changes on future systems.

Parking is an accepted interval request, not proof of zero internal work or exact
hourly deliveries. Diagnostics are `isParked`, `completeFrames`, `deliveredSize`,
and `lastFrameTime`. The helper serializes operations, rejects retired frames,
uses a five-second startup/parking deadline, and allows at most two delayed
recovery attempts before requiring `retry()` or a lifecycle transition.

## Lifecycle and shutdown

Both helpers suspend on system/display sleep, minimization, and close, and restart
on eligible wake/display events while enabled. The host must still call
`setVisible` on every show/hide/background-Off path. Keep one session for the HUD
window, not one per theme or view rebuild. These lifecycle handlers are included;
all game/display combinations have not been validated.

**67:** `setVisible(false)` unregisters synchronously. At normal app termination,
call it before returning `.terminateNow`. `await shutdown()` is also available
when replacing/releasing the helper from an asynchronous host operation.

**68:** stop is asynchronous. Retain the helper and `await shutdown()` before
replacing it or completing the host's coordinated quit. If implementing AppKit's
deferred termination, allow `applicationShouldTerminate` to return `.terminateLater`
before replying with `reply(toApplicationShouldTerminate: true)`; do not synchronously
block the main thread. Ordinary show/hide operations are serialized internally.

If a future update returns successful registration/parking but the game remains
Direct and capped, treat the workaround as ineffective despite `isActive` being
true. Stop it and use a deliberate user/developer choice of the separate alternative
or a plain background. This package does not silently switch implementations.

## What has and has not been established

The approved GlassTest look is regular native glass with Soft test 2. Both light
and dark are exported here. User reports established live blur and uncapped,
Composited presentation with 67 and 68 in the tested games. Earlier method-56 and
custom-glass FPS numbers are not re-labelled as method-67 benchmarks.

The export removes the old live backdrop capture/shader pipeline from its primary
path. It does not promise a specific FPS gain, zero display latency, or future OS
compatibility. A full PerformanceHUD migration still needs its own ordinary
gameplay/visibility check at the production HUD size. Other recording apps can
also change presentation, so compare with those stopped when diagnosing this helper.

For the supported native glass API, see Apple's
[NSGlassEffectView reference](https://developer.apple.com/documentation/appkit/nsglasseffectview)
and [AppKit design session](https://developer.apple.com/videos/play/wwdc2025/310/).
