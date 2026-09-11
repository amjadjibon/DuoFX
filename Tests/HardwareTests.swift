import XCTest
@testable import DuoFX

final class HardwareTests: XCTestCase {
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
