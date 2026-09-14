# DuoFX

A native macOS menu-bar app that animates the built-in desktop as a MacBook lid closes. Choose a blur sweep, progressive Soft fold, or an optional perspective tilt. The capture, sensor, and lifecycle architecture comes from [DESIGN.md](DESIGN.md).

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

1. Click **Enable effect** in the menu. New installations use **Lid sensor + Live desktop**; the active input and content are shown in **Settings → Setup**.
2. Close the lid below the angle shown by the Ready status in Settings (93° with the default calibration). The effect is intentionally hidden above that threshold. In **Settings → Setup**, use **Use current lid angle** to calibrate to your normal lid position.
3. Allow Screen Recording when macOS requests it. If macOS requires a restart after granting access, quit and reopen DuoFX, then enable it again.
4. **Setup → Diagnostics & recovery** reports sensor discovery, angle readings, unsupported reports, and read failures. Select **Setup → Input → Lid sensor** to follow physical movement; explicit selections are preserved on relaunch.
5. Try the bundled desktop using **Play demo**, the preview scrubber, or **Open / Halfway / Closed**. These controls change only the in-window preview and need no permission. **Follow lid** mirrors the actual effect when enabled with Lid sensor selected. To put the sample over the whole screen, select **Setup → Manual control + Sample desktop**, enable the effect, and lower **Desktop angle**.

Use **Pause all effects** in the menu at any time. Settings stays above the overlay and the overlay never accepts mouse or keyboard focus. Escape pauses when DuoFX receives the key event; global Escape can be unavailable without macOS input permission. DuoFX does not request that extra permission. The menu remains accessible.

Closing Settings with the red close button leaves DuoFX enabled. Capture discovery includes offscreen windows and retains an invisible discovery window while capturing, so the blur can start from the menu bar even before Settings has ever opened.

Optional **Sound effects** add a soft whoosh for opening and closing. Turn them on in the menu bar or **Settings → Sound**, adjust **Volume**, and use **Opening / Closing** to listen even while the effect is paused. Sound is off by default. Each sweep direction plays once, with movement thresholds to avoid chatter from the lid sensor. Muting, pausing, sleep, and quitting stop playback. Playback uses the Mac’s audio output and does not change system volume or record audio.

The original whoosh assets are bundled with the app and can be regenerated with `python3 scripts/generate-sounds.py`.

For a gentle sweep, use **Settings → Effect → Use recommended settings**: 18 px blur, 0.22 edge softness, 0.18 dimming, 0.20 s motion easing, and 25% sound volume. The preset preserves your working/minimum lid angles and whether sound is enabled. Dimming is scaled by the shader, so this setting darkens the fully blurred region by about 6%. The easing value controls response rather than a fixed animation duration; the sweep settles about 95% of the way to a new lid angle in 0.47 seconds. Increase **Motion easing** for a slower feel or reduce it for a quicker response.

**Settings → Effect → Animation** offers **Blur sweep** and **Soft fold**. Soft fold adapts the progressive blur and darkening from [iPhone Duo](https://iphone-duo-tawny.vercel.app/) to a moving top-to-bottom transition. Blur increases continuously behind the leading edge, followed by a deeper shadow as the lid closes. Desktop coordinates remain fixed. **Direction** supports all four edges; opening the lid reverses the same path. **Fold shadow** adjusts darkness, including black at high strength, and **Transition width** spreads the blur/shadow gradient. Blur, soft edge, dimming, and motion easing remain adjustable in either mode.

**Use reference look** selects Soft fold moving top to bottom, with 100% blur intensity (up to a 72-source-pixel sampling radius), 20% soft edge, 70% fold shadow, 24% transition width, no extra dimming, and 0.28 s easing. It preserves lid calibration and sound preferences. **Use recommended settings** returns to the original top-to-bottom Cinematic Frost sweep. Existing saved configurations retain their chosen animation and settings. The adapted sampler's MIT license is bundled as `IPhoneDuoLicense.txt`; phone models and reference media are not included.

**Settings → Effect → Animation → Perspective** tilts the captured desktop toward the destination edge over a black backdrop, while retaining the progressive blur and shadow. Top-to-bottom motion anchors the bottom edge like a laptop hinge. **Perspective strength** adjusts the tilt from 0% (identical to Soft fold) to 100% (up to 75°); the initial strength is 55%. Opening reverses the projection. Use **Play demo** to try it in the sample preview. This is a visual transformation: mouse targets stay at their original desktop positions. Existing installations keep their selected animation until Perspective is chosen.

**Edge fade** softens the three moving perspective edges into the backdrop. It defaults to 6% of the shorter display dimension and can be adjusted from 0% (crisp antialiased edges) to 20% (a broad fade). The fade grows gently as the tilt starts and recedes as the lid opens; the hinge stays anchored. It is independent of the blur's **Soft edge** control.

Visible animation follows Metal's display refresh callbacks, requesting up to 120 FPS on supported displays. Sensor/capture sampling remains at 60 Hz; intermediate animation frames use continuous easing. A timer keeps lid detection running when the overlay is hidden or drawing stops. Blur sweep and Soft fold keep desktop coordinates fixed; Perspective projects the captured image around its hinge.

### Permission enabled but capture still denied

Older DuoFX builds used ad-hoc signatures, which changed the application's identity on rebuild. macOS may retain an enabled switch for the previous identity while denying the replacement. The current project uses certificate signing to keep its identity stable across builds. [Apple confirms this signing behavior](https://developer.apple.com/forums/thread/819406).

When upgrading from an old build, quit DuoFX, remove its existing entry from **System Settings → Privacy & Security → Screen Recording**, add **`/Applications/DuoFX.app`** again (or your custom installation path), enable it, and reopen the app. Add the installed app rather than a copy in a DMG or build folder. This one-time reauthorization remains a macOS permission decision; the installer does not edit privacy databases or grant access automatically.

## Included

- A full-screen Metal quad with MPS Gaussian blur for Blur sweep and a GPU mip pyramid with variable-radius sampling for Soft fold and Perspective. Perspective uses inverse planar projection with antialiased moving edges. Opening the lid reverses the same path. Settings control blur, edge softness, shading, direction, tilt strength, and motion easing.
- Silk, Shade, and Frost presets; working/minimum angle calibration; persisted appearance and input choices. Enabling is intentionally not persisted.
- A deterministic bundled PNG for permission-free development and an embedded Metal preview that only redraws when settings change.
- Built-in-display-only ScreenCaptureKit capture at up to 60 FPS, BGRA IOSurface textures, complete-frame filtering, no cursor or audio, and exclusion of every DuoFX window.
- Newest-frame storage, retained Core Video owners through GPU completion, a three-command in-flight limit, and a serial capture lifecycle that rejects stale callbacks.
- Asynchronous HID discovery/polling on a dedicated queue, Apple vendor/product and usage checks, bounded report decoding, repeated-read failure handling, and explicit device teardown.
- Time-based angle smoothing, signed velocity, and hysteresis. Capture stops when the overlay becomes hidden, when paused, on sleep/session inactivity/lock, and on quit. Screen configuration changes rebuild the capture target.

All captured content stays on the device in memory. The app has no network, analytics, audio recording, or frame-saving functionality. Blur sweep and Soft fold leave the uncovered desktop transparent and preserve desktop coordinates. Perspective covers the original desktop with the tilted capture and a black backdrop. Settings and menu controls remain above all effects; mouse input always passes through to the original desktop positions.

## Validation

```sh
swift test
xcodebuild -project DuoFX.xcodeproj -scheme DuoFX \
  -configuration Release -derivedDataPath build build
```

Tests cover mapping boundaries, smoothing/velocity, hysteresis, blur coverage, report decoding, presets, settings migration, persistence, manual-provider lifecycle, and capture startup/pause/source-switch/failure/sleep/quit races using a controlled capture provider. Offscreen Metal tests compile the actual shader and verify fixed desktop coordinates and transparent uncovered regions for the blur modes, progressive blur/shadow, and opening reversal. Perspective tests check projected content, hinge anchoring in every direction, the opaque backdrop, zero-strength equivalence to Soft fold, and settings persistence. These tests do not request Screen Recording permission or display a full-screen overlay. GPU/display-dependent tests explicitly skip if their hardware is absent.

To render open, half-closed, and closed snapshots of the bundled fixture, run `DUOFX_PREVIEW_SNAPSHOTS=/tmp/duofx-preview swift test --filter RenderingTests`. Only the bundled test image is saved; captured desktop content is never used by these tests.

`DUOFX_RENDER_BENCHMARK=1 swift test --filter RenderingPerformanceTests` reports GPU p50/p95/p99 times for a synthetic 3024×1964 frame at sweep blur radii 0, 12, and 18, plus Soft fold and Perspective at maximum blur. This measures rendering cost, not achieved onscreen FPS or capture latency.

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

After adding source files, regenerate the checked-in Xcode project with `python3 scripts/generate-project.py`. The technical orientation fixture can be regenerated into `build/fixtures/Orientation.png` with `python3 scripts/generate-preview.py`. This does not overwrite the bundled artwork. Neither script needs third-party packages.

`scripts/generate-icon.sh` regenerates the bundled `.icns` app icon using AppKit and `iconutil`. The menu-bar icon is a native template image that adapts to light/dark appearances; both icons share the folding-laptop drawing in `MenuBarIcon.swift`.

## Packaging

`bash scripts/package.sh` creates `build/DuoFX.dmg` containing the Release app and an Applications link. This is a **local development build**, signed with Apple Development and not notarized.

To install an existing DMG without rebuilding, use `./scripts/install.sh build/DuoFX.dmg`. You can also open the DMG in Finder, drag DuoFX to Applications, and launch it there.

For distribution, use your Apple Developer team and Developer ID Application certificate in Xcode, archive the Release scheme, export with Developer ID signing and hardened runtime, notarize with `xcrun notarytool submit --wait`, and staple with `xcrun stapler staple`. Create a DMG from that signed and stapled app and validate it on another supported Mac. Developer ID signing, notarization, and installation on a second Mac require credentials/hardware and are not performed by the local packaging script. Launch at login and sound effects are not included.

## Attribution

HID matching constants and the feature-report reader are adapted from [Sam Gold's LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor), under Apache-2.0. See [NOTICE](NOTICE) and [the original license](Licenses/LidAngleSensor.txt), both included in the app bundle. Other implementation and the bundled preview image are original to DuoFX.

The bundled sample desktop is original generated artwork; its source prompt and provenance are in [docs/preview-art.md](docs/preview-art.md). Settings supports light/dark appearance, keyboard-accessible controls, and Reduce Motion (manual preview changes are immediate and automatic demos are disabled). A settled preview pauses its render loop.

To export offscreen light/dark layout checks at the minimum window size, run `DUOFX_SETTINGS_SNAPSHOTS=/tmp/duofx-settings swift test --filter SettingsLayoutTests`. AppKit bitmap snapshots omit the Metal surface; use the separate rendering snapshots above to verify the actual preview image and blur.
