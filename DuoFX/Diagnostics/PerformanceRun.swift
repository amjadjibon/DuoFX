import AppKit
#if SWIFT_PACKAGE
import DuoFXCore
#endif

/// Opt-in numeric telemetry. Normal launches allocate no recorder or frame history.
final class PerformanceRun: @unchecked Sendable {
    static let shared: PerformanceRun? = ProcessInfo.processInfo.environment["DUOFX_PERFORMANCE_REPORT"]
        .flatMap { $0.isEmpty ? nil : PerformanceRun(path: $0) }
    struct Event: Codable {
        var name: String
        var time: Double
        var value: Double
        var session: Int
    }
    private let path: String
    private let lock = NSLock()
    private var events: [Event] = []
    private var currentSession = 0
    private init(path: String) { self.path = path }
    var session: Int {
        lock.lock(); defer { lock.unlock() }
        return currentSession
    }
    func beginSession() {
        lock.lock(); currentSession += 1; lock.unlock()
        record("target")
    }
    func record(_ name: String, value: Double = 0, at time: Double = ProcessInfo.processInfo.systemUptime,
                session: Int? = nil) {
        lock.lock(); defer { lock.unlock() }
        // Bound memory if an interrupted diagnostic process is left running.
        guard events.count < 200_000 else { return }
        events.append(Event(name: name, time: time, value: value, session: session ?? currentSession))
    }

    @MainActor
    static func makeModel() -> AppModel {
        guard shared != nil else { return AppModel() }
        // A separate temporary domain prevents replay from changing real preferences.
        let defaults = UserDefaults(suiteName: "DuoFX.Performance.\(ProcessInfo.processInfo.processIdentifier)")!
        let model = AppModel(defaults: defaults)
        model.configuration = AppModel().configuration
        return model
    }

    @MainActor
    func start(model: AppModel, coordinator: EffectCoordinator) {
        Task { @MainActor in
            model.angleSource = .manual
            model.desktopSource = .liveDesktop
            model.motionPreference = .full
            model.configuration.animationMode = .perspective
            model.configuration.soundEnabled = false
            let measuredConfiguration = model.configuration
            model.manualAngle = model.configuration.workingAngle + 10
            // Existing access only: an unattended run must not wait on a permission dialog.
            if !CGPreflightScreenCaptureAccess() {
                model.errorMessage = "Performance run requires existing Screen Recording access for this installed app."
            } else {
                await phase("paused-before", seconds: 20, model: model)
                model.isEnabled = true
                await phase("enabled-idle", seconds: 20, model: model)
                record("phase:repeated-starts")
                // Six 10-second closing/opening cycles with capture torn down in between.
                let start = ProcessInfo.processInfo.systemUptime
                while ProcessInfo.processInfo.systemUptime - start < 60 && model.errorMessage == nil && model.isEnabled {
                    let t = (ProcessInfo.processInfo.systemUptime - start).truncatingRemainder(dividingBy: 10)
                    let progress = t < 6 ? 0.5 - 0.5 * cos(t / 6 * 2 * .pi) : 0
                    model.manualAngle = model.configuration.workingAngle + 5
                        - progress * (model.configuration.workingAngle + 5 - model.configuration.minimumAngle)
                    try? await Task.sleep(for: .milliseconds(16))
                }
                if model.isEnabled && model.errorMessage == nil {
                    model.manualAngle = (model.configuration.workingAngle + model.configuration.minimumAngle) / 2
                    await phase("held-half-closed", seconds: 30, model: model)
                }
                model.pause()
                await phase("paused-after", seconds: 20, model: model)
            }
            model.pause()
            try? await Task.sleep(for: .milliseconds(300))
            do { try write(configuration: measuredConfiguration, error: model.errorMessage) }
            catch { fputs("Could not write performance report: \(error)\n", stderr) }
            UserDefaults.standard.removePersistentDomain(forName: "DuoFX.Performance.\(ProcessInfo.processInfo.processIdentifier)")
            // Leave the cooperative task before AppKit enters its termination
            // loop, so the delegate's async cleanup can run on the main actor.
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }

    @MainActor
    private func phase(_ name: String, seconds: Double, model: AppModel) async {
        record("phase:\(name)")
        let until = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < until && model.errorMessage == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    @MainActor
    private func write(configuration: EffectConfiguration, error: String?) throws {
        struct Report: Encodable {
            var events: [Event]
            var configuration: EffectConfiguration
            var refreshHz: Int
            var width: Int
            var height: Int
            var os: String
            var error: String?
        }
        let screen = OverlayWindowController.builtInScreen()
        let display = screen.flatMap(OverlayWindowController.displayID)
        let report = Report(events: snapshot(), configuration: configuration,
                            refreshHz: screen?.maximumFramesPerSecond ?? 0,
                            width: display.map { CGDisplayPixelsWide($0) } ?? 0,
                            height: display.map { CGDisplayPixelsHigh($0) } ?? 0,
                            os: ProcessInfo.processInfo.operatingSystemVersionString, error: error)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func snapshot() -> [Event] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}
