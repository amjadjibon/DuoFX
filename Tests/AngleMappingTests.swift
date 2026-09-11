import XCTest
@testable import DuoFXCore

final class AngleMappingTests: XCTestCase {
    func testWorkingMinimumAndOutOfRangeAngles() {
        for (angle, expected): (Double, Float) in [(140, 0), (95, 0), (60, 0.5), (25, 1), (0, 1), (-10, 1)] {
            XCTAssertEqual(closingProgress(angle: angle, workingAngle: 95, minimumAngle: 25), expected, accuracy: 0.00001)
        }
    }
    func testDegenerateCalibrationAndInvalidInputRemainFinite() {
        XCTAssertEqual(closingProgress(angle: 94, workingAngle: 95, minimumAngle: 95), 1)
        XCTAssertEqual(closingProgress(angle: .nan, workingAngle: 95, minimumAngle: 25), 0)
        XCTAssertEqual(closingProgress(angle: 50, workingAngle: .infinity, minimumAngle: 25), 0)
    }
    func testHysteresisDoesNotChatter() {
        var gate = VisibilityGate()
        XCTAssertFalse(gate.update(angle: 94, workingAngle: 95))
        XCTAssertTrue(gate.update(angle: 92.9, workingAngle: 95))
        for angle in [93.1, 94, 93, 94.4] { XCTAssertTrue(gate.update(angle: angle, workingAngle: 95)) }
        XCTAssertFalse(gate.update(angle: 94.5, workingAngle: 95))
        XCTAssertFalse(gate.update(angle: 93.1, workingAngle: 95))
        XCTAssertFalse(gate.update(angle: .nan, workingAngle: 95))
    }
    func testFadeThresholdAndCompletion() {
        XCTAssertEqual(fadeAmount(progress: 0.71, start: 0.72), 0)
        XCTAssertEqual(fadeAmount(progress: 0.72, start: 0.72), 0)
        XCTAssertEqual(fadeAmount(progress: 0.86, start: 0.72), 0.5, accuracy: 0.00001)
        XCTAssertEqual(fadeAmount(progress: 1, start: 0.72), 1)
    }
    func testReportDecoderRejectsUnknownLayouts() {
        XCTAssertEqual(LidReport.decode([1, 95, 0, 0, 0, 0, 0, 0]), 95)
        XCTAssertEqual(LidReport.decode([1, 180, 0]), 180)
        XCTAssertEqual(LidReport.decode([1, 0, 0]), 0)
        XCTAssertNil(LidReport.decode([]))
        XCTAssertNil(LidReport.decode([1, 95]))
        XCTAssertNil(LidReport.decode([2, 95, 0]))
        XCTAssertNil(LidReport.decode([1, 0, 1]))
        XCTAssertNil(LidReport.decode([1, 95, 0, 0, 0, 0, 0, 0, 0]))
    }
}
