import XCTest
@testable import DuoFXCore

final class BlurSweepTests: XCTestCase {
    func testOpenIsClearAndClosedIsFullyCoveredIncludingEdges() {
        for y: Float in [0, 0.01, 0.25, 0.5, 0.75, 0.99, 1] {
            XCTAssertEqual(blurCoverage(y: y, progress: 0, edgeSoftness: 0.12), 0, accuracy: 0.00001)
            XCTAssertEqual(blurCoverage(y: y, progress: 1, edgeSoftness: 0.12), 1, accuracy: 0.00001)
        }
    }

    func testHalfClosedBlursTopAndLeavesBottomClear() {
        XCTAssertEqual(blurCoverage(y: 0.1, progress: 0.5, edgeSoftness: 0.12), 1)
        XCTAssertEqual(blurCoverage(y: 0.5, progress: 0.5, edgeSoftness: 0.12), 0.5, accuracy: 0.00001)
        XCTAssertEqual(blurCoverage(y: 0.9, progress: 0.5, edgeSoftness: 0.12), 0)
    }

    func testBoundaryMovesDownAndReversesWithoutHysteresisInTheShader() {
        let progress: [Float] = [0, 0.25, 0.5, 0.75, 1]
        let closing = progress.map { blurCoverage(y: 0.5, progress: $0, edgeSoftness: 0.12) }
        XCTAssertEqual(closing, closing.sorted())
        let opening = progress.reversed().map { blurCoverage(y: 0.5, progress: $0, edgeSoftness: 0.12) }
        XCTAssertEqual(opening, closing.reversed())
    }

    func testStylePresetsAndConfigurationValidation() {
        XCTAssertLessThan(EffectStyle.silk.preset.blurStrength, EffectStyle.frost.preset.blurStrength)
        XCTAssertGreaterThan(EffectStyle.shade.preset.shadowStrength, EffectStyle.frost.preset.shadowStrength)
        var c = EffectConfiguration()
        c.workingAngle = 70; c.minimumAngle = 100; c.blurStrength = .nan; c.edgeSoftness = 0
        let valid = c.validated()
        XCTAssertEqual(valid.minimumAngle, 65)
        XCTAssertEqual(valid.blurStrength, 18)
        XCTAssertEqual(valid.edgeSoftness, 0.02)
        c.apply(.silk)
        XCTAssertEqual(c.workingAngle, 70)
        XCTAssertEqual(c.edgeSoftness, EffectStyle.silk.preset.edgeSoftness)
    }

    func testRecommendedPresetKeepsCalibrationAndSoundChoice() {
        var c = EffectConfiguration()
        c.workingAngle = 115; c.minimumAngle = 30; c.soundEnabled = true
        c.blurStrength = 2; c.motionResponse = 0.08
        c.applyRecommended()
        XCTAssertEqual(c.style, .frost)
        XCTAssertEqual(c.blurStrength, 18)
        XCTAssertEqual(c.edgeSoftness, 0.22)
        XCTAssertEqual(c.shadowStrength, 0.18)
        XCTAssertEqual(c.motionResponse, 0.20)
        XCTAssertEqual(c.soundVolume, 0.25)
        XCTAssertEqual(c.workingAngle, 115)
        XCTAssertEqual(c.minimumAngle, 30)
        XCTAssertTrue(c.soundEnabled)
    }

    func testFoldReferencePreservesCalibrationAndSoundAndValidatesShadow() {
        var c = EffectConfiguration()
        c.workingAngle = 115; c.minimumAngle = 30; c.soundEnabled = true; c.soundVolume = 0.6
        c.applyFoldReference()
        XCTAssertEqual(c.animationMode, .fold)
        XCTAssertEqual(c.sweepDirection, .down)
        XCTAssertEqual(c.workingAngle, 115)
        XCTAssertEqual(c.minimumAngle, 30)
        XCTAssertTrue(c.soundEnabled)
        XCTAssertEqual(c.soundVolume, 0.6)
        XCTAssertEqual(c.blurStrength, 30)
        XCTAssertEqual(c.foldShadow, 0.70)
        XCTAssertEqual(c.foldWidth, 0.24)
        XCTAssertEqual(c.motionResponse, 0.28)
        XCTAssertEqual(c.validated(), c)
        c.foldWidth = 0; c.foldShadow = 2
        XCTAssertEqual(c.validated().foldWidth, 0.04)
        XCTAssertEqual(c.validated().foldShadow, 1)
        c.foldWidth = .nan; c.foldShadow = .infinity
        XCTAssertEqual(c.validated().foldWidth, 0.18)
        XCTAssertEqual(c.validated().foldShadow, 0.55)
        c.applyRecommended()
        XCTAssertEqual(c.animationMode, .sweep)
        XCTAssertEqual(c.sweepDirection, .down)
    }
}
