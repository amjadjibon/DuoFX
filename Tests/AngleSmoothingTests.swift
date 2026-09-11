import XCTest
@testable import DuoFXCore

final class AngleSmoothingTests: XCTestCase {
    func testFirstSampleDoesNotAnimateFromZero() {
        var smoother = AngleSmoother()
        XCTAssertEqual(smoother.update(95, at: 1), 95)
        XCTAssertEqual(smoother.velocity, 0)
    }
    func testSmoothingAndSignedVelocity() {
        var smoother = AngleSmoother()
        smoother.update(95, at: 0)
        XCTAssertEqual(smoother.update(85, at: 1.0 / 60), 93.2, accuracy: 0.00001)
        XCTAssertEqual(smoother.velocity, -108, accuracy: 0.00001)
    }
    func testIndependentOfSamplingRate() {
        var fast = AngleSmoother(), slow = AngleSmoother()
        fast.update(95, at: 0); slow.update(95, at: 0)
        for n in 1...60 { fast.update(60, at: Double(n) / 60) }
        for n in 1...30 { slow.update(60, at: Double(n) / 30) }
        XCTAssertEqual(fast.angle!, slow.angle!, accuracy: 0.00001)
    }
    func testWakeGapAndInvalidSamples() {
        var smoother = AngleSmoother()
        smoother.update(95, at: 0)
        XCTAssertEqual(smoother.update(60, at: 2), 60)
        XCTAssertEqual(smoother.velocity, 0)
        XCTAssertEqual(smoother.update(.nan, at: 3), 60)
    }
}
