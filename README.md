# DuoFX

A native macOS menu-bar app that sweeps blur down the built-in desktop as a MacBook lid closes. The desktop remains fixed in place. The capture, sensor, and lifecycle architecture comes from [DESIGN.md](DESIGN.md); the original folding projection has been replaced by a blur sweep.

Requires **macOS 14 or later, Apple silicon, and Xcode 15 or later**. Build and automated validation were performed with Xcode 26.6. Physical sensor support depends on the Mac's HID interface; manual preview is available independently.

## Run

Build a Release DMG, install it into `/Applications`, and launch DuoFX with one command:

```sh
./scripts/build-and-install.sh
```

The installer mounts the DMG, verifies and copies `DuoFX.app`, gracefully quits an older running copy before replacing it, ejects the image, and launches the installed app. If `/Applications` is not writable, use `./scripts/build-and-install.sh "$HOME/Applications"`. It does not use `sudo` or change your macOS security settings.

Click the **folding-laptop icon in the top menu bar** for **Enable effect**, **Pause all effects**, **Settings…** (⌘,), and **Quit DuoFX** (⌘Q). DuoFX runs as a menu-bar app, so it does not add a Dock icon.

Open `DuoFX.xcodeproj`, select the **DuoFX** scheme and **My Mac**, and Run. The app appears as a laptop icon in the menu bar. The project and scripts use an **Apple Development** certificate from your keychain so macOS can recognize the same application across rebuilds. Create one through Xcode's account settings if needed. To choose a particular existing certificate, set `SIGNING_IDENTITY` to its name or fingerprint when running the build script.

The build script writes the chosen certificate fingerprint and team to ignored `Signing.local.xcconfig`. Xcode also reads this file through `Signing.xcconfig`. Run `python3 scripts/configure-signing.py` once before building directly from a fresh Xcode checkout, or select your certificate/team in Xcode. The script uses existing keychain identities and never creates or exports private keys.

Or build the app from Terminal:

```sh
bash scripts/build.sh
open build/Build/Products/Debug/DuoFX.app
```

1. Click **Enable effect** in the menu. New installations use **Lid sensor + Live desktop**; the active input and content are shown in the menu and Settings.
2. Close the lid below the angle shown by the Ready status (93° with the default calibration). The effect is intentionally hidden above that threshold. In **Settings → Controls**, use **Use current angle as working angle** to calibrate to your normal lid position.
3. Allow Screen Recording when macOS requests it. If macOS requires a restart after granting access, quit and reopen DuoFX, then enable it again.
4. **Diagnostics** reports sensor discovery, angle readings, unsupported reports, and read failures. If you previously selected **Manual preview**, switch **Controls → Angle control** to **Lid sensor** to follow physical movement; explicit selections are preserved on relaunch.
5. For permission-free testing, keep the effect paused and move **Preview angle** in Settings. To show this preview over the screen, choose **Manual preview + Bundled image** in Controls, enable the effect, and lower the preview angle.

Use **Pause all effects** in the menu at any time. Settings stays above the overlay and the overlay never accepts mouse or keyboard focus. Escape pauses when DuoFX receives the key event; global Escape can be unavailable without macOS input permission. DuoFX does not request that extra permission. The menu remains accessible.

Closing Settings with the red close button leaves DuoFX enabled. Capture discovery includes offscreen windows and retains an invisible discovery window while capturing, so the blur can start from the menu bar even before Settings has ever opened.

### Permission enabled but capture still denied

Older DuoFX builds used ad-hoc signatures, which changed the application's identity on rebuild. macOS may retain an enabled switch for the previous identity while denying the replacement. The current project uses certificate signing to keep its identity stable across builds. [Apple confirms this signing behavior](https://developer.apple.com/forums/thread/819406).

When upgrading from an old build, quit DuoFX, remove its existing entry from **System Settings → Privacy & Security → Screen Recording**, add **`/Applications/DuoFX.app`** again (or your custom installation path), enable it, and reopen the app. Add the installed app rather than a copy in a DMG or build folder. This one-time reauthorization remains a macOS permission decision; the installer does not edit privacy databases or grant access automatically.

## Included

- A fixed full-screen Metal quad with MPS Gaussian blur and a soft boundary that travels from top to bottom. Opening the lid reverses the sweep. Settings control blur radius, edge softness, and dimming of the blurred area.
- Silk, Shade, and Frost presets; working/minimum angle calibration; persisted appearance and input choices. Enabling is intentionally not persisted.
- A deterministic bundled PNG for permission-free development and an embedded Metal preview that only redraws when settings change.
- Built-in-display-only ScreenCaptureKit capture at up to 60 FPS, BGRA IOSurface textures, complete-frame filtering, no cursor or audio, and exclusion of every DuoFX window.
- Newest-frame storage, retained Core Video owners through GPU completion, a three-command in-flight limit, and a serial capture lifecycle that rejects stale callbacks.
- Asynchronous HID discovery/polling on a dedicated queue, Apple vendor/product and usage checks, bounded report decoding, repeated-read failure handling, and explicit device teardown.
- Time-based angle smoothing, signed velocity, and hysteresis. Capture stops when the overlay becomes hidden, when paused, on sleep/session inactivity/lock, and on quit. Screen configuration changes rebuild the capture target.

All captured content stays on the device in memory. The app has no network, analytics, audio, or frame-saving functionality. The overlay is fully transparent below the blur boundary and samples the blurred desktop at its original coordinates above it. Settings and menu controls remain above the effect, and the real desktop receives mouse events at the same visual positions.

## Validation

```sh
swift test
xcodebuild -project DuoFX.xcodeproj -scheme DuoFX \
  -configuration Release -derivedDataPath build build
```

Tests cover mapping boundaries, smoothing/velocity, hysteresis, blur coverage, report decoding, presets, settings migration, persistence, manual-provider lifecycle, and capture startup/pause/source-switch/failure/sleep/quit races using a controlled capture provider. Offscreen Metal tests compile the actual shader and verify that desktop pixels never move, that only the covered region blurs, and that the uncovered overlay is transparent. They also check full blur coverage at the minimum angle and correct reversal when opening. These tests do not request Screen Recording permission or display a full-screen overlay. GPU/display-dependent tests explicitly skip if their hardware is absent.

To render open, half-closed, and closed snapshots of the bundled fixture, run `DUOFX_PREVIEW_SNAPSHOTS=/tmp/duofx-preview swift test --filter RenderingTests`. Only the bundled test image is saved; captured desktop content is never used by these tests.

To additionally probe the physical lid sensor, run `DUOFX_HARDWARE_TESTS=1 swift test --filter HardwareTests`. This samples the sensor briefly without moving the lid, requesting capture permission, or showing an overlay. It reports an explicit skip for unsupported hardware.

To check capture discovery with Settings closed, leave the installed DuoFX running with its effect paused and Settings closed, then run `DUOFX_CAPTURE_TESTS=1 swift test --filter HardwareTests/testCaptureDiscoveryIncludesDuoFXWithSettingsClosed`. This requires existing Screen Recording access for the test runner, queries app/window metadata without recording frames, and verifies DuoFX can still be excluded from capture without a visible window.

`DUOFX_CAPTURE_TESTS=1 swift test --filter HardwareTests/testCaptureDiscoveryBeforeAnySettingsWindowExists` checks discovery from a fresh process, verifies its discovery window stays offscreen, and confirms stopping capture releases that window.

`DUOFX_CAPTURE_TESTS=1 swift test --filter HardwareTests/testLiveCaptureStartsWithoutVisibleSettings` additionally starts real desktop capture without a visible window and checks that a frame arrives. Frames are discarded immediately without being saved or displayed.

On the development Mac (`Mac16,8`), the hardware probe successfully read 14 samples at 112°. This device advertises a one-byte maximum feature report despite returning a longer valid report; the reader treats the descriptor size as diagnostic information and validates the actual response. This confirms sensor discovery and reading on that machine, but does not replace the lid-motion checks below.

Before distributing, validate on the target MacBook:

- Grant/deny/revoke Screen Recording permission and test relaunch recovery.
- Confirm live capture never recursively captures the overlay, including in full-screen apps and other Spaces.
- Move the lid slowly and quickly, then hold it near the working-angle boundary.
- Lock/unlock, sleep/wake, and connect/disconnect an external display, including clamshell mode.
- Confirm menu/Settings access and mouse passthrough throughout the effect.
- Profile frame rate, GPU/CPU load, memory, and energy with Instruments at the built-in display's native resolution.

The automated suite does not establish physical lid tracking, actual Screen Recording permission behavior, multi-Space behavior, or sustained 60 FPS. HID report and screen-lock notification behavior are undocumented and may change across macOS versions.

## Project layout

`DuoFX/App` owns lifecycle and observation; `Sensor` owns HID and manual input; `Capture` owns ScreenCaptureKit; `Rendering` owns the overlay, textures, mesh, and shader; `Settings` contains the SwiftUI controls. Pure models and math compile as `DuoFXCore` for Swift Package tests. Xcode builds the same sources directly into the app.

Metal source is bundled and compiled once per renderer with `makeLibrary`, so a separate Metal command-line toolchain download is not required. Rendering pipelines, meshes, and samplers are retained. Blur kernels are rebuilt only when the quantized sigma changes, and the intermediate texture is reused until the source size changes.

After adding source files, regenerate the checked-in Xcode project with `python3 scripts/generate-project.py`. The fixture can be regenerated with `python3 scripts/generate-preview.py`. Neither script needs third-party packages.

`scripts/generate-icon.sh` regenerates the bundled `.icns` app icon using AppKit and `iconutil`. The menu-bar icon is a native template image that adapts to light/dark appearances; both icons share the folding-laptop drawing in `MenuBarIcon.swift`.

## Packaging

`bash scripts/package.sh` creates `build/DuoFX.dmg` containing the Release app and an Applications link. This is a **local development build**, signed with Apple Development and not notarized.

To install an existing DMG without rebuilding, use `./scripts/install.sh build/DuoFX.dmg`. You can also open the DMG in Finder, drag DuoFX to Applications, and launch it there.

For distribution, use your Apple Developer team and Developer ID Application certificate in Xcode, archive the Release scheme, export with Developer ID signing and hardened runtime, notarize with `xcrun notarytool submit --wait`, and staple with `xcrun stapler staple`. Create a DMG from that signed and stapled app and validate it on another supported Mac. Developer ID signing, notarization, and installation on a second Mac require credentials/hardware and are not performed by the local packaging script. Launch at login and sound effects are not included.

## Attribution

HID matching constants and the feature-report reader are adapted from [Sam Gold's LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor), under Apache-2.0. See [NOTICE](NOTICE) and [the original license](Licenses/LidAngleSensor.txt), both included in the app bundle. Other implementation and the bundled preview image are original to DuoFX.
