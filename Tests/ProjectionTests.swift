import XCTest
@testable import DuoFXCore

final class ProjectionTests: XCTestCase {
    func testOpenPanelIsIdentity() {
        for point: SIMD2<Float> in [[-1, -1], [1, 1], [0.25, -0.3]] {
            let projected = projectPoint(point, progress: 0, configuration: .init())
            XCTAssertEqual(projected.x, point.x, accuracy: 0.00001)
            XCTAssertEqual(projected.y, point.y, accuracy: 0.00001)
        }
    }
    func testHingeRemainsFixedThroughoutRotation() {
        for p: Float in [0, 0.25, 0.5, 0.75, 1] {
            XCTAssertEqual(projectPoint([-1, -1], progress: p, configuration: .init()), [-1, -1])
            XCTAssertEqual(projectPoint([1, -1], progress: p, configuration: .init()), [1, -1])
        }
    }
    func testFortyFiveDegreeProjectionAgainstReference() {
        var c = EffectConfiguration()
        c.perspective = 1; c.viewerDistance = 2; c.verticalStretch = 0
        // Rotated top = (x:1, y:sqrt(1/2), z:sqrt(1/2)); perspective divide by 1 + z/2.
        let projected = projectPoint([1, 1], progress: 0.5, configuration: c)
        XCTAssertEqual(projected.x, 0.738796125, accuracy: 0.00001)
        XCTAssertEqual(projected.y, 0.04481550, accuracy: 0.00001)
    }
    func testClosedPanelCollapsesToHinge() {
        XCTAssertEqual(projectPoint([0, 1], progress: 1, configuration: .init()).y, -1, accuracy: 0.00001)
    }
    func testStylePresetsAndConfigurationValidation() {
        XCTAssertLessThan(EffectStyle.silk.preset.blurStrength, EffectStyle.frost.preset.blurStrength)
        XCTAssertGreaterThan(EffectStyle.shade.preset.shadowStrength, EffectStyle.frost.preset.shadowStrength)
        var c = EffectConfiguration()
        c.workingAngle = 70; c.minimumAngle = 100; c.blurStrength = .nan
        c.viewerDistance = 0; c.perspective = 4
        let valid = c.validated()
        XCTAssertEqual(valid.minimumAngle, 65)
        XCTAssertEqual(valid.blurStrength, 12)
        XCTAssertEqual(valid.viewerDistance, 1)
        XCTAssertEqual(valid.perspective, 1)
        c.apply(.silk)
        XCTAssertEqual(c.workingAngle, 70)
        XCTAssertEqual(c.style, .silk)
    }
}
