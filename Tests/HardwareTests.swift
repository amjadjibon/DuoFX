import XCTest
import AppKit
import ScreenCaptureKit
@testable import DuoFX

final class HardwareTests: XCTestCase {
    @MainActor
    func testCaptureDiscoveryIncludesDuoFXWithSettingsClosed() async throws {
        guard ProcessInfo.processInfo.environment["DUOFX_CAPTURE_TESTS"] == "1" else {
            throw XCTSkip("Opt in with DUOFX_CAPTURE_TESTS=1 while DuoFX is running with Settings closed")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("The test runner needs existing Screen Recording access; this test does not request it")
        }
        let app = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.amjadjibon.duofx").first,
                               "Run the installed DuoFX app before this test")
        let all = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let ownWindows = all.windows.filter { $0.owningApplication?.processID == app.processIdentifier }
        guard !ownWindows.isEmpty, ownWindows.allSatisfy({ !$0.isOnScreen }) else {
            throw XCTSkip("Close DuoFX Settings and pause its overlay before this test")
        }
        let service = ScreenCaptureService()
        let discovered = try await service.shareableContent()
        await service.stop()
        XCTAssertTrue(discovered.applications.contains { $0.processID == app.processIdentifier },
                      "Capture must find DuoFX to exclude its overlay even with Settings closed")
    }

    @MainActor
    func testCaptureDiscoveryBeforeAnySettingsWindowExists() async throws {
        guard ProcessInfo.processInfo.environment["DUOFX_CAPTURE_TESTS"] == "1",
              CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Opt in with DUOFX_CAPTURE_TESTS=1 and existing Screen Recording access")
        }
        _ = NSApplication.shared
        let service = ScreenCaptureService()
        let discovered = try await service.shareableContent()
        let pid = ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(discovered.applications.contains { $0.processID == pid },
                      "A fresh process must be discoverable without opening Settings")
        let ownWindows = discovered.windows.filter { $0.owningApplication?.processID == pid }
        XCTAssertFalse(ownWindows.isEmpty)
        XCTAssertTrue(ownWindows.allSatisfy { !$0.isOnScreen }, "Discovery must never show a window")
        await service.stop()
        let stopped = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        XCTAssertFalse(stopped.windows.contains { $0.owningApplication?.processID == pid },
                       "Stopping capture must release the discovery window")
    }

    @MainActor
    func testLiveCaptureStartsWithoutVisibleSettings() async throws {
        guard ProcessInfo.processInfo.environment["DUOFX_CAPTURE_TESTS"] == "1",
              CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Opt in with DUOFX_CAPTURE_TESTS=1 and existing Screen Recording access")
        }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(OverlayWindowController.builtInScreen())
        let displayID = try XCTUnwrap(OverlayWindowController.displayID(for: screen))
        let service = ScreenCaptureService()
        let firstFrame = expectation(description: "Headless capture receives a desktop frame")
        // Discard frames immediately; this test never saves or displays them.
        try await service.start(displayID: displayID, onFrame: { _ in firstFrame.fulfill() },
                                onFailure: { error in XCTFail(error.localizedDescription) })
        await fulfillment(of: [firstFrame], timeout: 5)
        await service.stop()
    }

    @MainActor
    func testPhysicalSensorReportsValidAngles() async throws {
        guard ProcessInfo.processInfo.environment["DUOFX_HARDWARE_TESTS"] == "1" else {
            throw XCTSkip("Opt in with DUOFX_HARDWARE_TESTS=1 to read the physical lid sensor")
        }
        let sensor = HIDAngleSensor()
        var readings: [Double] = []
        var diagnostic: SensorDiagnostic?
        sensor.onReading = { readings.append($0) }
        sensor.onDiagnostic = { diagnostic = $0 }
        sensor.start()
        defer { sensor.stop() }
        for _ in 0..<100 {
            if diagnostic != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let result = try XCTUnwrap(diagnostic, "Sensor discovery did not respond within two seconds")
        print("DuoFX hardware: \(result.model) · \(result.message)")
        guard result.isAvailable else { throw XCTSkip(result.message) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(readings.count, 1)
        XCTAssertTrue(readings.allSatisfy { $0.isFinite && (0...180).contains($0) })
        print("DuoFX hardware: \(readings.count) samples; last angle \(readings.last ?? -1)°")
    }
}
