import AppKit
import CoreVideo
import Metal
import XCTest
@testable import DuoFX
@testable import DuoFXCore

@MainActor
final class LifecycleTests: XCTestCase {
    private func fixture() throws -> (AppModel, DelayedCapture, RecordingOverlay, EffectCoordinator, String) {
        guard MTLCreateSystemDefaultDevice() != nil, let screen = NSScreen.screens.first else {
            throw XCTSkip("A display and Metal are required for coordinator integration tests")
        }
        let suite = "DuoFXLifecycle.\(UUID().uuidString)"
        let model = AppModel(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        model.angleSource = .manual
        model.desktopSource = .liveDesktop; model.manualAngle = 60; model.isEnabled = true
        let capture = DelayedCapture()
        let overlay = RecordingOverlay()
        let coordinator = EffectCoordinator(model: model, capture: capture, overlay: overlay, screenProvider: { screen })
        return (model, capture, overlay, coordinator, suite)
    }

    func testPauseDuringCaptureStartupCannotReopenOverlay() async throws {
        let (model, capture, overlay, coordinator, suite) = try fixture()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        coordinator.start()
        await waitUntil { capture.startCount == 1 }
        coordinator.pause()
        capture.finishStart()
        capture.deliverFrame()
        await waitUntil { capture.stopCount >= 2 }
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isCapturing)
        XCTAssertFalse(capture.isRunning)
        XCTAssertEqual(overlay.showCount, 0)
        await coordinator.shutdown()
    }

    func testSwitchToPreviewDiscardsOldFrameAndStopsCapture() async throws {
        let (model, capture, overlay, coordinator, suite) = try fixture()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        coordinator.start()
        await waitUntil { capture.startCount == 1 }
        model.desktopSource = .testImage
        // Let observation deliver the changed source before the pending stream returns.
        await waitUntil { overlay.hideCount >= 2 }
        capture.finishStart()
        capture.deliverFrame()
        await waitUntil { overlay.showCount == 1 }
        XCTAssertFalse(capture.isRunning)
        XCTAssertFalse(model.isCapturing)
        XCTAssertEqual(model.status, "Bundled image preview")
        XCTAssertEqual(overlay.showCount, 1)
        await coordinator.shutdown()
    }

    func testCaptureFailurePausesAndReleasesResources() async throws {
        let (model, capture, overlay, coordinator, suite) = try fixture()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        coordinator.start()
        await waitUntil { capture.startCount == 1 }
        capture.finishStart()
        capture.deliverFrame()
        await waitUntil { overlay.showCount == 1 }
        capture.fail()
        await waitUntil { !model.isEnabled && !capture.isRunning }
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isCapturing)
        await coordinator.shutdown()
    }

    func testWorkingAngleDoesNotStartCapture() async throws {
        let (model, capture, overlay, coordinator, suite) = try fixture()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        model.manualAngle = model.configuration.workingAngle
        coordinator.start()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(capture.startCount, 0)
        XCTAssertEqual(overlay.showCount, 0)
        await coordinator.shutdown()
    }

    func testSleepStopsCaptureAndWakeRestartsIt() async throws {
        let (model, capture, overlay, coordinator, suite) = try fixture()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        coordinator.start()
        await waitUntil { capture.startCount == 1 }
        capture.finishStart(); capture.deliverFrame()
        await waitUntil { overlay.showCount == 1 }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        await waitUntil { !capture.isRunning }
        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.isCapturing)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitUntil { capture.startCount == 2 }
        capture.finishStart(); capture.deliverFrame()
        await waitUntil { overlay.showCount == 2 }
        await coordinator.shutdown()
    }

    func testShutdownWaitsForPendingStartAndClosesIt() async throws {
        let (_, capture, overlay, coordinator, suite) = try fixture()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        coordinator.start()
        await waitUntil { capture.startCount == 1 }
        let shutdown = Task { await coordinator.shutdown() }
        await waitUntil { overlay.hideCount >= 2 }
        capture.finishStart(); capture.deliverFrame()
        await shutdown.value
        XCTAssertFalse(capture.isRunning)
        XCTAssertEqual(overlay.showCount, 0)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for lifecycle transition", file: file, line: line)
    }
}

@MainActor
private final class DelayedCapture: ScreenCapturing {
    var startCount = 0
    var stopCount = 0
    var isRunning = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var onFrame: (@Sendable (CVPixelBuffer) -> Void)?
    private var onFailure: (@Sendable (Error) -> Void)?
    // Intentionally keep callbacks alive to exercise the coordinator's stale-token guard.
    func invalidate() {}
    func start(displayID: CGDirectDisplayID,
               onFrame: @escaping @Sendable (CVPixelBuffer) -> Void,
               onFailure: @escaping @Sendable (Error) -> Void) async throws {
        self.onFrame = onFrame; self.onFailure = onFailure; startCount += 1
        await withCheckedContinuation { continuation = $0 }
        isRunning = true
    }
    func finishStart() { continuation?.resume(); continuation = nil }
    func stop() async { stopCount += 1; isRunning = false }
    func fail() { onFailure?(CaptureError.stalePermission) }
    func deliverFrame() {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        XCTAssertEqual(result, kCVReturnSuccess)
        if let buffer { onFrame?(buffer) }
    }
}

@MainActor
private final class RecordingOverlay: OverlayPresenting {
    var showCount = 0
    var hideCount = 0
    func show(renderer: MetalRenderer, on screen: NSScreen) { showCount += 1 }
    func hide() { hideCount += 1 }
}
