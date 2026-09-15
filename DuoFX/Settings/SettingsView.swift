import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import DuoFXCore
#endif

struct SettingsView: View {
    @Bindable var model: AppModel
    var previewSound: (LidSound) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var section = SettingsSection.appearance
    @State private var previewPosition = 0.35
    @State private var followsLid = false
    @State private var demoTask: Task<Void, Never>?
    @State private var previewError: String?
    private static let appIcon = AppResources.bundle.url(forResource: "DuoFX", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:)) ?? NSApplication.shared.applicationIconImage!

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case appearance = "Effect", sound = "Sound", setup = "Setup"
        var id: Self { self }
    }
    private var accent: Color {
        colorScheme == .dark ? Color(red: 0.36, green: 0.78, blue: 0.76) : Color(red: 0.12, green: 0.48, blue: 0.48)
    }
    private var progress: Float { followsLid && model.isEnabled ? model.progress : Float(previewPosition) }
    private var displayedAngle: Double {
        model.configuration.workingAngle - Double(progress) * (model.configuration.workingAngle - model.configuration.minimumAngle)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                previewPane.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                Divider()
                VStack(spacing: 16) {
                    Picker("Settings section", selection: $section) {
                        ForEach(SettingsSection.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            switch section {
                            case .appearance: appearanceControls
                            case .sound: soundControls
                            case .setup: setupControls
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                }.padding(22).frame(width: 334)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            }
            if let error = model.errorMessage { errorBanner(error) }
            Divider()
            footer
        }
        .frame(minWidth: 900, idealWidth: 980, minHeight: 670, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .background(SettingsWindowLevel())
        .onDisappear { stopDemo() }
        .onChange(of: model.isEnabled) { _, enabled in
            if !enabled { followsLid = false; stopDemo() }
        }
        .onChange(of: model.angleSource) { _, source in
            if source != .sensor { followsLid = false }
        }
        .onChange(of: reduceMotion) { _, reduced in if reduced { stopDemo() } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: Self.appIcon)
                .resizable().frame(width: 42, height: 42).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("DuoFX").font(.system(size: 23, weight: .semibold, design: .rounded))
                Text("A softer close.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Toggle("Enable effect", isOn: $model.isEnabled).toggleStyle(.switch)
                Text(model.isEnabled ? "Runs with Settings closed" : "Try the preview before enabling")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 26).padding(.vertical, 18)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview").font(.title2.weight(.semibold))
                    Label("Sample desktop · Preview only", systemImage: "photo")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    demoTask == nil ? playDemo() : stopDemo()
                } label: {
                    Label(demoTask == nil ? "Play demo" : "Stop demo", systemImage: demoTask == nil ? "play.fill" : "stop.fill")
                }.buttonStyle(.bordered).disabled(followsLid || reduceMotion)
                    .help(reduceMotion ? "Automatic demos are disabled while Reduce Motion is on" : "Preview a closing and opening sweep")
            }
            Group {
                if let previewError {
                    ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle",
                        description: Text(previewError))
                } else {
                    MetalPreview(configuration: model.configuration, progress: progress,
                                 easesChanges: !followsLid && !reduceMotion, error: $previewError)
                        .accessibilityLabel("Sample desktop, \(model.configuration.sweepDirection.title), blur progress \(Int(progress * 100)) percent")
                }
            }
            .aspectRatio(1.5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.09), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 7)

            VStack(spacing: 8) {
                Slider(value: Binding(get: { Double(progress) }, set: {
                    stopDemo(); previewPosition = $0
                }), in: 0...1)
                    .disabled(followsLid)
                    .accessibilityLabel("Preview blur coverage")
                    .accessibilityValue("\(Int(progress * 100)) percent")
                HStack {
                    positionButton("Open", value: 0)
                    Spacer()
                    positionButton("Halfway", value: 0.5)
                    Spacer()
                    positionButton("Closed", value: 1)
                }.font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Toggle("Follow lid", isOn: Binding(get: { followsLid }, set: {
                    stopDemo(); followsLid = $0
                })).toggleStyle(.switch).controlSize(.small)
                    .disabled(!model.isEnabled || model.angleSource != .sensor)
                    .help("Enable the effect with Lid sensor selected to mirror your MacBook’s lid in the preview")
                Spacer()
                Text("\(Int(displayedAngle.rounded()))° · \(Int(progress * 100))% covered")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var appearanceControls: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeading("Animation", detail: "Choose how your desktop responds to the lid.")
                Picker("Animation", selection: $model.configuration.animationMode) {
                    Text("Blur sweep").tag(AnimationMode.sweep)
                    Text("Soft fold").tag(AnimationMode.fold)
                    Text("Perspective").tag(AnimationMode.perspective)
                }.pickerStyle(.segmented).labelsHidden()
                Picker("Direction", selection: $model.configuration.sweepDirection) {
                    ForEach(SweepDirection.allCases) { Text($0.title).tag($0) }
                }
                Button("Use reference look") { model.configuration.applyFoldReference() }
                    .help("Progressive blur and shadow inspired by iPhone Duo, flowing top to bottom.")
                if model.configuration.animationMode == .perspective {
                    adjustment("Perspective strength", detail: "Tilt the captured desktop toward the hinge", value: $model.configuration.perspectiveStrength,
                               range: 0...1, display: percent(model.configuration.perspectiveStrength))
                    adjustment("Edge fade", detail: "Soften the tilted outline into the dark backdrop", value: $model.configuration.perspectiveFeather,
                               range: 0...0.2, display: percent(model.configuration.perspectiveFeather))
                    Text("Tilts the desktop image over a dark backdrop. Mouse targets stay in their original positions. Try Play demo first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.configuration.animationMode != .sweep {
                    Text(model.configuration.animationMode == .fold
                         ? "Blur builds behind the moving edge as you close the lid, followed by a deepening shadow. Your desktop stays in place."
                         : "Blur and shadow build as the desktop tilts. Set perspective strength to zero for the fixed-desktop Soft fold look.")
                        .font(.caption).foregroundStyle(.secondary)
                    adjustment("Fold shadow", detail: "Darken the area behind the moving blur", value: $model.configuration.foldShadow,
                               range: 0...1, display: percent(model.configuration.foldShadow))
                    adjustment("Transition width", detail: "Higher values spread the blur and shadow", value: $model.configuration.foldWidth,
                               range: 0.04...0.35, display: percent(model.configuration.foldWidth))
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                sectionHeading("Your look", detail: "Choose a starting point, then make it yours.")
                ForEach(EffectStyle.allCases) { style in
                    styleButton(style)
                }
                Button("Use recommended settings") { model.configuration.applyRecommended() }
                    .font(.caption).help("Cinematic Frost with gentle easing and quiet sound. Keeps your calibration and sound toggle.")
            }
            Divider()
            VStack(spacing: 20) {
                adjustment("Blur", detail: "How soft the covered area becomes", value: $model.configuration.blurStrength,
                           range: 0...30, display: model.configuration.animationMode != .sweep
                           ? percent(model.configuration.blurStrength / 30) : "\(Int(model.configuration.blurStrength.rounded())) px")
                adjustment("Soft edge", detail: "Blend the boundary into your desktop", value: $model.configuration.edgeSoftness,
                           range: 0.02...0.3, display: percent(model.configuration.edgeSoftness))
                adjustment("Dimming", detail: "Shade the blurred area gently", value: $model.configuration.shadowStrength,
                           range: 0...1, display: percent(model.configuration.shadowStrength))
                adjustment("Motion easing", detail: "Higher values feel slower and softer", value: $model.configuration.motionResponse,
                           range: 0.08...0.4, display: String(format: "%.2f s", model.configuration.motionResponse))
            }
        }
    }

    private var soundControls: some View {
        Group {
            sectionHeading("A little atmosphere", detail: "Soft whooshes for opening and closing.")
            Toggle("Sound effects", isOn: $model.configuration.soundEnabled).toggleStyle(.switch)
            adjustment("Volume", detail: "Independent of your Mac’s volume", value: $model.configuration.soundVolume,
                       range: 0...1, display: percent(model.configuration.soundVolume))
            HStack {
                Button { previewSound(.opening) } label: { Label("Opening", systemImage: "speaker.wave.2") }
                Button { previewSound(.closing) } label: { Label("Closing", systemImage: "speaker.wave.2") }
            }.disabled(model.configuration.soundVolume == 0)
            Text("Click either sound to listen, even while the effect is paused. Sound stops when you pause, sleep, or quit.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var setupControls: some View {
        Group {
            sectionHeading("Connect to your Mac", detail: "Set how DuoFX follows your lid.")
            VStack(alignment: .leading, spacing: 14) {
                Picker("Input", selection: $model.angleSource) {
                    Text("Lid sensor").tag(AngleSource.sensor)
                    Text("Manual control").tag(AngleSource.manual)
                }
                Picker("Desktop", selection: $model.desktopSource) {
                    Text("Live desktop").tag(DesktopSource.liveDesktop)
                    Text("Sample desktop").tag(DesktopSource.testImage)
                }
                if model.angleSource == .manual {
                    adjustment("Desktop angle", detail: "Moves the full-screen effect when enabled", value: $model.manualAngle,
                               range: 0...140, display: "\(Int(model.manualAngle))°")
                }
            }
            Divider()
            sectionHeading("Lid calibration", detail: "Your working angle is clear. Your minimum angle is fully blurred.")
            adjustment("Working angle", detail: "Your normal open-lid position",
                       value: Binding(get: { model.configuration.workingAngle }, set: {
                           model.configuration.workingAngle = $0
                           model.configuration = model.configuration.validated()
                       }), range: 40...140, display: "\(Int(model.configuration.workingAngle))°")
            adjustment("Minimum angle", detail: "Where the blur reaches the bottom", value: $model.configuration.minimumAngle,
                       range: 0...(model.configuration.workingAngle - 5), display: "\(Int(model.configuration.minimumAngle))°")
            Button("Use current lid angle") {
                model.configuration.workingAngle = model.angleSource == .manual ? model.manualAngle : model.currentAngle
                model.configuration = model.configuration.validated()
            }.disabled(model.angleSource == .sensor && (!model.isEnabled || !model.sensorDiagnostic.isAvailable))
            Divider()
            sectionHeading("Screen Recording", detail: "Needed only for Live desktop. The sample preview works without permission.")
            Button("Open macOS permissions…") { openPermissions() }
            Text("DuoFX processes frames on this Mac. It never saves your screen, records audio, or uploads content.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Diagnostics & recovery") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.sensorDiagnostic.model).font(.headline)
                    Text(model.sensorDiagnostic.message)
                    LabeledContent("Lid angle", value: String(format: "%.1f°", model.currentAngle))
                    LabeledContent("Velocity", value: String(format: "%.1f°/s", model.velocity))
                    Text(model.sensorDiagnostic.properties).font(.caption.monospaced()).textSelection(.enabled)
                    Text("If permission was just granted, quit and reopen DuoFX. If an older build remains authorized, remove its Screen Recording entry and add the installed app again.")
                    Button("Use manual control") { model.pause(); model.angleSource = .manual }
                }.font(.caption).padding(.top, 12)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.errorMessage != nil ? Color.orange : model.isEnabled ? accent : .secondary)
                .frame(width: 7, height: 7).accessibilityHidden(true)
            Text(model.status).lineLimit(1).help(model.status)
            Spacer()
            Label("On this Mac only", systemImage: "lock.shield").foregroundStyle(.secondary)
            Button("Pause all effects") { stopDemo(); model.pause() }.keyboardShortcut(.cancelAction)
        }.font(.caption).padding(.horizontal, 24).padding(.vertical, 13)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button("Open setup") { section = .setup }
        }.padding(14).background(Color.orange.opacity(0.08))
    }

    private func styleButton(_ style: EffectStyle) -> some View {
        let selected = model.configuration.style == style
        let subtitle: String = switch style {
        case .silk: "A light touch"
        case .shade: "Deeper focus"
        case .frost: "Soft and cinematic"
        }
        return Button { model.configuration.apply(style) } label: {
            HStack(spacing: 10) {
                Image(systemName: style == .silk ? "wind" : style == .shade ? "moon" : "cloud.fog")
                    .font(.title3).frame(width: 26).foregroundStyle(selected ? accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.rawValue.capitalized).font(.callout.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
            }.padding(11).frame(maxWidth: .infinity)
                .background(selected ? accent.opacity(0.09) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? accent.opacity(0.45) : .primary.opacity(0.07)))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func adjustment(_ title: String, detail: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                Text(display).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).accessibilityLabel(title).accessibilityValue(display)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func positionButton(_ title: String, value: Double) -> some View {
        Button(title) { stopDemo(); previewPosition = value }.buttonStyle(.plain).disabled(followsLid)
    }
    private func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    private func stopDemo() { demoTask?.cancel(); demoTask = nil }
    private func playDemo() {
        stopDemo(); followsLid = false; previewPosition = 0
        demoTask = Task { @MainActor in
            let start = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                if elapsed >= 4.8 { break }
                previewPosition = 0.5 - 0.5 * cos(elapsed / 4.8 * 2 * .pi)
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            previewPosition = 0; demoTask = nil
        }
    }
}

/// Keep controls above the effect, without making the overlay accept focus.
private struct SettingsWindowLevel: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowProbe() }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class WindowProbe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.level = .mainMenu
        }
    }
}
