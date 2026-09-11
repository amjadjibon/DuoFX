import AppKit
import MetalKit
import SwiftUI
#if SWIFT_PACKAGE
import DuoFXCore
#endif

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var previewError: String?

    private var previewProgress: Float {
        closingProgress(angle: model.angleSource == .sensor && model.isEnabled ? model.currentAngle : model.manualAngle,
                        workingAngle: model.configuration.workingAngle, minimumAngle: model.configuration.minimumAngle)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer").font(.system(size: 30)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DuoFX").font(.title2.bold())
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enable effect", isOn: $model.isEnabled).toggleStyle(.switch)
            }.padding(20)
            Divider()
            TabView {
                effectTab.tabItem { Label("Effect", systemImage: "square.3.layers.3d") }
                controlsTab.tabItem { Label("Controls", systemImage: "slider.horizontal.3") }
                diagnosticsTab.tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
            }.padding(12)
            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 12)
            }
            Divider()
            HStack {
                Label(model.isCapturing ? "Capturing · no audio · never saved" : "Screen capture stopped",
                      systemImage: model.isCapturing ? "record.circle" : "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Pause all effects") { model.pause() }.keyboardShortcut(.cancelAction)
            }.padding(16)
        }
        .frame(width: 590, height: 700)
        .background(SettingsWindowLevel())
    }

    private var effectTab: some View {
        VStack(spacing: 14) {
            if let previewError {
                ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text(previewError)).frame(height: 220)
            } else {
                MetalPreview(configuration: model.configuration, progress: previewProgress,
                             error: $previewError)
                    .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topLeading) {
                        Text("BUNDLED IMAGE PREVIEW").font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(7).background(.black.opacity(0.65), in: Capsule())
                            .foregroundStyle(.white).padding(10)
                    }
                    .accessibilityLabel("Folding effect preview")
            }
            Form {
                Picker("Style", selection: Binding(get: { model.configuration.style },
                                                   set: { model.configuration.apply($0) })) {
                    ForEach(EffectStyle.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }.pickerStyle(.segmented)
                parameter("Preview angle", value: $model.manualAngle, range: 0...140, suffix: "°")
                    .disabled(model.angleSource == .sensor && model.isEnabled)
                parameter("Perspective", value: $model.configuration.perspective, range: 0...1)
                parameter("Vertical stretch", value: $model.configuration.verticalStretch, range: 0...1)
                parameter("Blur", value: $model.configuration.blurStrength, range: 0...30, suffix: " px")
                parameter("Shadow", value: $model.configuration.shadowStrength, range: 0...1)
                parameter("Fade begins", value: $model.configuration.fadeStart, range: 0.3...0.95)
            }.formStyle(.grouped)
        }.padding(8)
    }

    private var controlsTab: some View {
        Form {
            Section("Input") {
                Picker("Angle control", selection: $model.angleSource) {
                    Text("Manual preview").tag(AngleSource.manual)
                    Text("Lid sensor").tag(AngleSource.sensor)
                }
                Picker("Overlay content", selection: $model.desktopSource) {
                    Text("Bundled image").tag(DesktopSource.testImage)
                    Text("Live desktop").tag(DesktopSource.liveDesktop)
                }
                Text("Enable the effect, then lower the preview angle or move the lid below your working angle. The overlay appears only on the built-in display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Calibration") {
                parameter("Working angle", value: Binding(get: { model.configuration.workingAngle }, set: {
                    model.configuration.workingAngle = $0
                    model.configuration = model.configuration.validated()
                }), range: 40...140, suffix: "°")
                parameter("Minimum angle", value: $model.configuration.minimumAngle,
                          range: 0...(model.configuration.workingAngle - 5), suffix: "°")
                Button("Use current angle as working angle") {
                    model.configuration.workingAngle = model.angleSource == .manual ? model.manualAngle : model.currentAngle
                    model.configuration = model.configuration.validated()
                }.disabled(model.angleSource == .sensor && !model.sensorDiagnostic.isAvailable)
                parameter("Viewer distance", value: $model.configuration.viewerDistance, range: 1...6, suffix: "×")
                Text("Viewer distance is measured in display heights. The lower edge stays fixed at the hinge.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Screen Recording") {
                Text("Live desktop needs Screen Recording permission to transform your display. Frames stay in GPU memory on this Mac. DuoFX does not capture audio, save frames, or send them over the network.")
                Button("Open Screen Recording settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Text("After granting permission, quit and reopen DuoFX if capture does not start.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var diagnosticsTab: some View {
        Form {
            Section("Lid sensor") {
                LabeledContent("Mac", value: model.sensorDiagnostic.model)
                Text(model.sensorDiagnostic.message).textSelection(.enabled)
                Text(model.sensorDiagnostic.properties).font(.caption.monospaced()).textSelection(.enabled)
                LabeledContent("Smoothed angle", value: String(format: "%.1f°", model.currentAngle))
                LabeledContent("Velocity", value: String(format: "%.1f°/s", model.velocity))
                LabeledContent("Closing progress", value: String(format: "%.0f%%", model.progress * 100))
                Button("Use manual preview") { model.isEnabled = false; model.angleSource = .manual }
                Text("The lid sensor uses an undocumented hardware report. An unsupported sensor never prevents manual preview. To retry detection, select Lid sensor and enable the effect again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Recovery") {
                Text("Pause all effects is always available in the menu bar. Escape also pauses while DuoFX receives key events; global Escape depends on macOS input permissions. Capture stops at the working angle, on pause, and while the screen sleeps or the session is inactive.")
                Button("Restore default appearance") { model.configuration = EffectConfiguration() }
            }
        }.formStyle(.grouped)
    }

    private func parameter(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String = "") -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: value, in: range).accessibilityLabel(title)
                Text(suffix == "°" ? String(format: "%.0f°", value.wrappedValue)
                     : String(format: "%.2f%@", value.wrappedValue, suffix))
                    .font(.caption.monospacedDigit()).frame(width: 60, alignment: .trailing)
            }.frame(width: 270)
        }
    }
}

private struct MetalPreview: NSViewRepresentable {
    var configuration: EffectConfiguration
    var progress: Float
    @Binding var error: String?
    final class Coordinator { var renderer: MetalRenderer? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.isPaused = true; view.enableSetNeedsDisplay = true
        view.colorPixelFormat = .bgra8Unorm
        do {
            let renderer = try MetalRenderer()
            renderer.isOverlay = false
            renderer.onFailure = { failure in
                DispatchQueue.main.async { self.error = failure.localizedDescription }
            }
            try renderer.loadPreview()
            view.device = renderer.device; view.delegate = renderer
            context.coordinator.renderer = renderer
        } catch {
            DispatchQueue.main.async { self.error = error.localizedDescription }
        }
        return view
    }
    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.configuration = configuration
        context.coordinator.renderer?.progress = progress
        view.needsDisplay = true
    }
    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil; coordinator.renderer?.clear(); coordinator.renderer = nil
    }
}

/// Keep the controls readable because all of DuoFX's windows are excluded from capture.
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
