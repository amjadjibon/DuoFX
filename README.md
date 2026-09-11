# DuoFX

A native macOS menu-bar app that folds the built-in desktop as a MacBook lid closes. Implements the capture, sensor, rendering, settings, and lifecycle architecture in [DESIGN.md](DESIGN.md).

Requires **macOS 14 or later, Apple silicon, and Xcode 15 or later**. Build and automated validation were performed with Xcode 26.6. Physical sensor support depends on the Mac's HID interface; manual preview is available independently.

## Run

Build a Release DMG, install it into `/Applications`, and launch DuoFX with one command:

```sh
./scripts/build-and-install.sh
```

The installer mounts the DMG, verifies and copies `DuoFX.app`, gracefully quits an older running copy before replacing it, ejects the image, and launches the installed app. If `/Applications` is not writable, use `./scripts/build-and-install.sh "$HOME/Applications"`. It does not use `sudo` or change your macOS security settings.

Click the **folding-laptop icon in the top menu bar** for **Enable effect**, **Pause all effects**, **Settings…** (⌘,), and **Quit DuoFX** (⌘Q). DuoFX runs as a menu-bar app, so it does not add a Dock icon.

Open `DuoFX.xcodeproj`, select the **DuoFX** scheme and **My Mac**, and Run. The app appears as a laptop icon in the menu bar. The project uses local ad-hoc signing and does not require a developer account.

Or build the app from Terminal:

```sh
bash scripts/build.sh
open build/Build/Products/Debug/DuoFX.app
```

1. Open **Settings…** from the laptop menu icon.
2. Move **Preview angle** to inspect the bundled image inside Settings. This needs no permission and works with the effect paused.
3. Enable the effect to show that image over the built-in screen. Below the working angle, the panel folds; at the working angle, the overlay disappears.
4. In **Controls**, choose **Live desktop** to capture the built-in display. Enable the effect and lower the preview angle to request Screen Recording permission. If macOS requires it, quit and reopen DuoFX after granting access.
5. Choose **Lid sensor** to use the physical lid. **Diagnostics** reports discovery, unsupported reports, and read failures. Use **Manual preview** if detection fails.

Use **Pause all effects** in the menu at any time. Settings stays above the overlay and the overlay never accepts mouse or keyboard focus. Escape pauses when DuoFX receives the key event; global Escape can be unavailable without macOS input permission. DuoFX does not request that extra permission. The menu remains accessible.

## Included

- A 64-segment hinge-anchored Metal mesh with perspective-correct texture interpolation, adjustable viewing distance and stretch, MPS Gaussian blur, shading, and fade to black.
- Silk, Shade, and Frost presets; working/minimum angle calibration; persisted appearance and input choices. Enabling is intentionally not persisted.
- A deterministic bundled PNG for permission-free development and an embedded Metal preview that only redraws when settings change.
- Built-in-display-only ScreenCaptureKit capture at up to 60 FPS, BGRA IOSurface textures, complete-frame filtering, no cursor or audio, and exclusion of every DuoFX window.
- Newest-frame storage, retained Core Video owners through GPU completion, a three-command in-flight limit, and a serial capture lifecycle that rejects stale callbacks.
- Asynchronous HID discovery/polling on a dedicated queue, Apple vendor/product and usage checks, bounded report decoding, repeated-read failure handling, and explicit device teardown.
- Time-based angle smoothing, signed velocity, and hysteresis. Capture stops when the overlay becomes hidden, when paused, on sleep/session inactivity/lock, and on quit. Screen configuration changes rebuild the capture target.

All captured content stays on the device in memory. The app has no network, analytics, audio, or frame-saving functionality. A black backdrop masks the unfolded desktop outside the projected mesh. Settings and menu controls remain above it; the real desktop still receives mouse events, so its hit targets do not move with the visual effect.

## Validation

```sh
swift test
xcodebuild -project DuoFX.xcodeproj -scheme DuoFX \
  -configuration Release -derivedDataPath build build
```

Tests cover mapping boundaries, smoothing/velocity, hysteresis, fade, report decoding, independently calculated projection points, presets, persistence, manual-provider lifecycle, and capture startup/pause/source-switch/failure/sleep/quit races using a controlled capture provider. Offscreen Metal tests compile the actual shader and verify corner colors, texture orientation, masking, blur, transparency, and full fade at representative angles. These tests do not request Screen Recording permission or display a full-screen overlay. GPU/display-dependent tests explicitly skip if their hardware is absent.

To additionally probe the physical lid sensor, run `DUOFX_HARDWARE_TESTS=1 swift test --filter HardwareTests`. This samples the sensor briefly without moving the lid, requesting capture permission, or showing an overlay. It reports an explicit skip for unsupported hardware.

On the development Mac (`Mac16,8`), the hardware probe successfully read 14 samples at 112°. This device advertises a one-byte maximum feature report despite returning a longer valid report; the reader treats the descriptor size as diagnostic information and validates the actual response. This confirms sensor discovery and reading on that machine, but does not replace the lid-motion checks below.

Before distributing, validate on the target MacBook:

- Grant/deny/revoke Screen Recording permission and test relaunch recovery.
- Confirm live capture never recursively captures the overlay, including in full-screen apps and other Spaces.
- Move the lid slowly and quickly, then hold it near the working-angle boundary.
- Lock/unlock, sleep/wake, and connect/disconnect an external display, including clamshell mode.
- Confirm menu/Settings access and mouse passthrough throughout the effect.
- Profile frame rate, GPU/CPU load, memory, and energy with Instruments at the built-in display's native resolution.

The automated suite does not establish physical lid tracking, actual Screen Recording permission behavior, multi-Space behavior, or sustained 60 FPS. The projection assumes a viewer aligned with the hinge; viewing distance is adjustable, but eye-height calibration is not implemented. HID report and screen-lock notification behavior are undocumented and may change across macOS versions.

## Project layout

`DuoFX/App` owns lifecycle and observation; `Sensor` owns HID and manual input; `Capture` owns ScreenCaptureKit; `Rendering` owns the overlay, textures, mesh, and shader; `Settings` contains the SwiftUI controls. Pure models and math compile as `DuoFXCore` for Swift Package tests. Xcode builds the same sources directly into the app.

Metal source is bundled and compiled once per renderer with `makeLibrary`, so a separate Metal command-line toolchain download is not required. Rendering pipelines, meshes, and samplers are retained. Blur kernels are rebuilt only when the quantized sigma changes, and the intermediate texture is reused until the source size changes.

After adding source files, regenerate the checked-in Xcode project with `python3 scripts/generate-project.py`. The fixture can be regenerated with `python3 scripts/generate-preview.py`. Neither script needs third-party packages.

`scripts/generate-icon.sh` regenerates the bundled `.icns` app icon using AppKit and `iconutil`. The menu-bar icon is a native template image that adapts to light/dark appearances; both icons share the folding-laptop drawing in `MenuBarIcon.swift`.

## Packaging

`bash scripts/package.sh` creates `build/DuoFX.dmg` containing the Release app and an Applications link. This is a **local development build**, ad-hoc signed and not notarized.

To install an existing DMG without rebuilding, use `./scripts/install.sh build/DuoFX.dmg`. You can also open the DMG in Finder, drag DuoFX to Applications, and launch it there.

For distribution, use your Apple Developer team and Developer ID Application certificate in Xcode, archive the Release scheme, export with Developer ID signing and hardened runtime, notarize with `xcrun notarytool submit --wait`, and staple with `xcrun stapler staple`. Create a DMG from that signed and stapled app and validate it on another supported Mac. Developer ID signing, notarization, and installation on a second Mac require credentials/hardware and are not performed by the local packaging script. Launch at login and sound effects are not included.

## Attribution

HID matching constants and the feature-report reader are adapted from [Sam Gold's LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor), under Apache-2.0. See [NOTICE](NOTICE) and [the original license](Licenses/LidAngleSensor.txt), both included in the app bundle. Other implementation and the bundled preview image are original to DuoFX.
