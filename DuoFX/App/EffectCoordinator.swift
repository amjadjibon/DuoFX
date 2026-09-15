import AppKit
import Observation
#if SWIFT_PACKAGE
import DuoFXCore
#endif

@MainActor
final class EffectCoordinator {
    private let model: AppModel
    private let sensor = HIDAngleSensor()
    private let capture: any ScreenCapturing
    private let overlay: any OverlayPresenting
    private let sound: any EffectSoundPlaying
    private var soundTrigger = LidSoundTrigger()
    private let screenProvider: @MainActor () -> NSScreen?
    private let now: @MainActor () -> TimeInterval
    private var renderer: MetalRenderer?
    private var timer: Timer?
    private var lastDrawTime = -Double.infinity
    private var awaitingPresentation = false
    private var presentationStart: TimeInterval?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var localEscape: Any?
    private var globalEscape: Any?
    private var suspensions: Set<String> = []
    private var source: AngleSource?
    private var rawAngle = 95.0
    private var smoother = AngleSmoother()
    private var gate = VisibilityGate()
    private var target: OutputTarget?
    private var revision = 0
    private var transition: Task<Void, Never>?
    private var firstFrameTask: Task<Void, Never>?
    private var hasFrame = false
    private var shuttingDown = false

    private struct OutputTarget: Equatable {
        var source: DesktopSource
        var display: CGDirectDisplayID
    }

    init(model: AppModel, capture: (any ScreenCapturing)? = nil,
         overlay: (any OverlayPresenting)? = nil,
         sound: (any EffectSoundPlaying)? = nil,
         screenProvider: @escaping @MainActor () -> NSScreen? = OverlayWindowController.builtInScreen,
         now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.model = model; self.capture = capture ?? ScreenCaptureService()
        self.overlay = overlay ?? OverlayWindowController()
        self.sound = sound ?? EffectSoundPlayer()
        self.screenProvider = screenProvider
        self.now = now
    }

    func start() {
        observeSettings()
        sensor.onReading = { [weak self] in self?.rawAngle = $0 }
        sensor.onDiagnostic = { [weak self] diagnostic in
            guard let self else { return }
            self.model.sensorDiagnostic = diagnostic
            if !diagnostic.isAvailable {
                self.model.errorMessage = diagnostic.message
                self.model.isEnabled = false
                self.refresh()
            }
        }
        installNotifications()
        localEscape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { self?.pause() } }
            return event
        }
        // Best effort: macOS may withhold global key events without Input Monitoring.
        // The menu's Pause command is always available and needs no extra permission.
        globalEscape = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { self?.pause() } }
        }
        refresh()
    }

    func pause() { model.isEnabled = false; refresh() }

    func previewSound(_ cue: LidSound) {
        sound.play(cue, volume: model.configuration.validated().soundVolume)
    }

    private func observeSettings() {
        withObservationTracking {
            _ = model.isEnabled; _ = model.configuration; _ = model.angleSource
            _ = model.desktopSource; _ = model.manualAngle
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.shuttingDown else { return }
                self.observeSettings(); self.refresh()
            }
        }
    }

    private func refresh() {
        guard !shuttingDown else { return }
        let active = model.isEnabled && suspensions.isEmpty
        sound.setVolume(model.configuration.validated().soundVolume)
        if !active || !model.configuration.soundEnabled {
            sound.stop(); soundTrigger = LidSoundTrigger()
        }
        if !active || source != model.angleSource {
            sound.stop(); soundTrigger = LidSoundTrigger()
            sensor.stop(); source = nil
            timer?.invalidate(); timer = nil
            smoother = AngleSmoother(); gate = VisibilityGate()
        }
        guard active else {
            setTarget(nil)
            model.status = model.isEnabled ? "Suspended while the screen is unavailable" : "Paused"
            return
        }
        if source == nil {
            model.errorMessage = nil
            source = model.angleSource
            rawAngle = model.configuration.workingAngle
            if source == .sensor { model.status = "Checking lid sensor…"; sensor.start() }
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // The display drives visible animation. Keep polling while
                    // hidden or if drawing stops, so lid/sleep recovery still works.
                    if !self.hasFrame || self.now() - self.lastDrawTime > 0.05 {
                        self.tick()
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common); self.timer = timer
        }
        tick()
    }

    private func tick() {
        guard model.isEnabled, suspensions.isEmpty, !shuttingDown else { return }
        let c = model.configuration.validated()
        let time = now()
        let inputAngle = source == .manual ? model.manualAngle : rawAngle
        let angle = smoother.update(inputAngle, at: time, response: c.motionResponse)
        model.currentAngle = angle; model.velocity = smoother.velocity
        model.progress = closingProgress(angle: angle, workingAngle: c.workingAngle, minimumAngle: c.minimumAngle)
        var visibleProgress = model.progress
        if c.animationMode == .perspective {
            if awaitingPresentation {
                visibleProgress = 0
            } else if let start = presentationStart {
                // Capture can start after the lid has already moved. Reveal the
                // tilt from zero on the display's clock, then track the lid
                // directly once caught up. Hidden/capture time never consumes it.
                let duration = c.motionResponse * 2
                visibleProgress *= smoothstep(0, Float(duration), Float(time - start))
                if time - start >= duration { presentationStart = nil }
            }
        }
        renderer?.configuration = c; renderer?.progress = visibleProgress
        if hasFrame && c.soundEnabled && c.soundVolume > 0 {
            if let cue = soundTrigger.update(progress: Double(model.progress), at: time) {
                sound.play(cue, volume: c.soundVolume)
            }
        } else {
            soundTrigger = LidSoundTrigger()
        }
        guard gate.update(angle: angle, workingAngle: c.workingAngle) else {
            setTarget(nil)
            let triggerAngle = Int((c.workingAngle - 2).rounded(.down))
            if source == .sensor {
                model.status = sensor.isAvailable ? "Ready · close lid below \(triggerAngle)°" : "Checking lid sensor…"
            } else {
                model.status = "Ready · lower preview angle below \(triggerAngle)°"
            }
            return
        }
        guard let screen = screenProvider(),
              let id = OverlayWindowController.displayID(for: screen) else {
            fail(CaptureError.noBuiltInDisplay); return
        }
        setTarget(OutputTarget(source: model.desktopSource, display: id))
    }

    private func setTarget(_ next: OutputTarget?) {
        guard next != target else { return }
        target = next; revision += 1
        sound.stop(); soundTrigger = LidSoundTrigger()
        // Hide synchronously. A pending permission dialog/start must never reopen it.
        capture.invalidate()
        overlay.hide(); renderer?.clear(); hasFrame = false
        awaitingPresentation = false; presentationStart = nil
        firstFrameTask?.cancel(); firstFrameTask = nil
        model.isCapturing = false
        if transition == nil {
            transition = Task { [weak self] in await self?.reconcile() }
        }
    }

    private func reconcile() async {
        // This is the sole owner of asynchronous stream start/stop operations.
        while true {
            let token = revision
            let desired = target
            await capture.stop()
            guard token == revision else { continue }
            renderer?.clear()
            guard let desired, !shuttingDown else { break }
            do {
                if renderer == nil { renderer = try MetalRenderer() }
                guard let renderer else { throw RendererError.unavailable }
                renderer.onWillDraw = { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.lastDrawTime = self.now()
                        if self.awaitingPresentation {
                            self.awaitingPresentation = false
                            self.presentationStart = self.lastDrawTime
                        }
                        self.tick()
                    }
                }
                renderer.configuration = model.configuration.validated(); renderer.progress = model.progress
                renderer.onFailure = { [weak self] error in
                    Task { @MainActor in
                        guard let self, self.revision == token else { return }
                        self.fail(error)
                    }
                }
                if desired.source == .testImage {
                    try renderer.loadPreview()
                    show(token: token)
                } else {
                    model.status = "Starting desktop capture…"
                    // Only the first accepted frame needs a main-actor notification.
                    let arrival = FirstFrameSignal()
                    try await capture.start(displayID: desired.display, onFrame: { [weak self, weak renderer] buffer in
                        guard let renderer else { return }
                        guard renderer.submit(buffer) else {
                            if arrival.claimFailure() {
                                Task { @MainActor in
                                    guard let self, self.revision == token else { return }
                                    self.fail(RendererError.textureCache)
                                }
                            }
                            return
                        }
                        if arrival.claimFirst() {
                            Task { @MainActor in self?.show(token: token) }
                        }
                    }, onFailure: { [weak self] error in
                        Task { @MainActor in
                            guard let self, self.revision == token else { return }
                            self.fail(error)
                        }
                    })
                    guard token == revision else { continue }
                    model.isCapturing = true
                    if !hasFrame {
                        firstFrameTask = Task { [weak self] in
                            do { try await Task.sleep(for: .seconds(5)) } catch { return }
                            guard let self, self.revision == token, !self.hasFrame else { return }
                            self.fail(CaptureError.stalePermission)
                        }
                    }
                }
            } catch {
                if token == revision { fail(error) }
            }
            if token == revision { break }
        }
        transition = nil
    }

    private func show(token: Int) {
        guard revision == token, target != nil, model.isEnabled, suspensions.isEmpty,
              !shuttingDown, let renderer,
              let screen = screenProvider() else { return }
        hasFrame = true; firstFrameTask?.cancel(); firstFrameTask = nil
        awaitingPresentation = model.configuration.animationMode == .perspective
        presentationStart = nil
        if awaitingPresentation { renderer.progress = 0 }
        overlay.show(renderer: renderer, on: screen)
        model.status = target?.source == .liveDesktop ? "Live desktop · on this Mac only" : "Bundled image preview"
    }

    private func fail(_ error: Error) {
        model.errorMessage = error.localizedDescription
        model.isEnabled = false
        refresh()
    }

    private func installNotifications() {
        func watch(_ center: NotificationCenter, _ name: Notification.Name,
                   _ action: @escaping @MainActor @Sendable () -> Void) {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { action() }
            }
            observers.append((center, observer))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, String, Bool)] = [
            (NSWorkspace.willSleepNotification, "sleep", true),
            (NSWorkspace.didWakeNotification, "sleep", false),
            (NSWorkspace.screensDidSleepNotification, "display", true),
            (NSWorkspace.screensDidWakeNotification, "display", false),
            (NSWorkspace.sessionDidResignActiveNotification, "session", true),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session", false)
        ]
        for (name, reason, suspended) in events {
            watch(workspace, name) { [weak self] in
                guard let self else { return }
                if suspended { self.suspensions.insert(reason) } else { self.suspensions.remove(reason) }
                self.refresh()
            }
        }
        // Workspace session notifications cover user switching; these distributed
        // notifications additionally cover locking an otherwise awake display.
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            watch(DistributedNotificationCenter.default(), Notification.Name(name)) { [weak self] in
                guard let self else { return }
                if locked { self.suspensions.insert("lock") } else { self.suspensions.remove("lock") }
                self.refresh()
            }
        }
        watch(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            guard let self else { return }
            self.setTarget(nil); self.refresh()
        }
    }

    func shutdown() async {
        shuttingDown = true; model.isEnabled = false
        sound.stop(); soundTrigger = LidSoundTrigger()
        timer?.invalidate(); timer = nil; sensor.stop()
        firstFrameTask?.cancel(); firstFrameTask = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        if let localEscape { NSEvent.removeMonitor(localEscape) }
        if let globalEscape { NSEvent.removeMonitor(globalEscape) }
        localEscape = nil; globalEscape = nil
        setTarget(nil)
        await transition?.value
        await capture.stop(); renderer?.clear(); overlay.hide()
    }
}

private final class FirstFrameSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var received = false
    private var failed = false
    func claimFirst() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !received else { return false }; received = true; return true
    }
    func claimFailure() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !failed else { return false }; failed = true; return true
    }
}
