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
        let first = smoother.update(85, at: 1.0 / 60)
        XCTAssertGreaterThan(first, 94.5, "Motion should ease into the first frame")
        XCTAssertLessThan(first, 95)
        XCTAssertLessThan(smoother.velocity, 0)
        _ = smoother.update(100, at: 2.0 / 60)
        XCTAssertTrue(smoother.velocity.isFinite)
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

    func testCinematicResponseIsMonotonicAndSettlesWithoutOvershoot() {
        var smoother = AngleSmoother()
        smoother.update(95, at: 0)
        var previous = 95.0
        for frame in 1...120 {
            let next = smoother.update(25, at: Double(frame) / 120)
            XCTAssertLessThanOrEqual(next, previous)
            XCTAssertGreaterThanOrEqual(next, 25)
            previous = next
        }
        XCTAssertEqual(previous, 25, accuracy: 0.05)
        // Reversing should recover smoothly and remain inside the angle range.
        for frame in 121...240 {
            let next = smoother.update(95, at: Double(frame) / 120)
            XCTAssertTrue((25...95).contains(next))
        }
        XCTAssertEqual(smoother.angle!, 95, accuracy: 0.05)
    }

    func testDisplayPacingProducesDistinctFramesAt120Hz() {
        var smoother = AngleSmoother()
        smoother.update(95, at: 0)
        let frames = (1...60).map { smoother.update(25, at: Double($0) / 120) }
        XCTAssertEqual(Set(frames).count, frames.count, "Every refresh should advance the sweep")
        var at60 = AngleSmoother()
        at60.update(95, at: 0)
        for frame in 1...30 { _ = at60.update(25, at: Double(frame) / 60) }
        XCTAssertEqual(frames.last!, at60.angle!, accuracy: 0.00001)
    }

    func testLongerResponseMakesTheSweepMoreGradual() {
        var quick = AngleSmoother(), cinematic = AngleSmoother()
        quick.update(95, at: 0); cinematic.update(95, at: 0)
        for frame in 1...12 {
            _ = quick.update(25, at: Double(frame) / 60, response: 0.08)
            _ = cinematic.update(25, at: Double(frame) / 60, response: 0.20)
        }
        XCTAssertGreaterThan(cinematic.angle!, quick.angle!)
        XCTAssertLessThan(cinematic.angle!, 60)
    }
}
