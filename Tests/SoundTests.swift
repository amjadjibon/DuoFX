import XCTest
@testable import DuoFX
@testable import DuoFXCore

final class SoundTests: XCTestCase {
    func testFirstReadingAndSensorJitterStaySilent() {
        var trigger = LidSoundTrigger()
        XCTAssertNil(trigger.update(progress: 0.5, at: 0))
        for i in 1...100 {
            XCTAssertNil(trigger.update(progress: i.isMultiple(of: 2) ? 0.51 : 0.49, at: Double(i) / 60))
        }
        XCTAssertNil(trigger.update(progress: .nan, at: 2))
    }

    func testEachDirectionPlaysOnceUntilARealReversal() {
        var trigger = LidSoundTrigger()
        XCTAssertNil(trigger.update(progress: 0, at: 0))
        XCTAssertEqual(trigger.update(progress: 0.04, at: 0.1), .closing)
        XCTAssertNil(trigger.update(progress: 0.4, at: 0.2))
        XCTAssertNil(trigger.update(progress: 0.8, at: 0.4))
        XCTAssertNil(trigger.update(progress: 0.79, at: 0.5))
        XCTAssertEqual(trigger.update(progress: 0.75, at: 0.6), .opening)
        XCTAssertNil(trigger.update(progress: 0.5, at: 0.8))
        XCTAssertNil(trigger.update(progress: 0.1, at: 1))
    }

    func testRapidReversalIsRateLimitedAndResetDoesNotPlay() {
        var trigger = LidSoundTrigger()
        _ = trigger.update(progress: 0.4, at: 0)
        XCTAssertEqual(trigger.update(progress: 0.5, at: 0.1), .closing)
        XCTAssertNil(trigger.update(progress: 0.4, at: 0.2))
        XCTAssertEqual(trigger.update(progress: 0.35, at: 0.5), .opening)
        trigger = LidSoundTrigger()
        XCTAssertNil(trigger.update(progress: 0.8, at: 1))
    }

    @MainActor
    func testBothBundledWhooshesDecodeWithoutPlaying() throws {
        for cue in [LidSound.opening, .closing] {
            let sound = try XCTUnwrap(EffectSoundPlayer.load(cue))
            XCTAssertEqual(sound.duration, 0.45, accuracy: 0.01)
            XCTAssertFalse(sound.isPlaying)
        }
    }

    func testVolumeValidationAndVisualPresetsPreserveSoundPreferences() {
        var configuration = EffectConfiguration()
        configuration.soundVolume = 5
        XCTAssertEqual(configuration.validated().soundVolume, 1)
        configuration.soundVolume = -1
        XCTAssertEqual(configuration.validated().soundVolume, 0)
        configuration.soundVolume = .nan
        XCTAssertEqual(configuration.validated().soundVolume, 0.35)
        configuration.soundVolume = 0.6; configuration.soundEnabled = true
        configuration.apply(.silk)
        XCTAssertTrue(configuration.soundEnabled)
        XCTAssertEqual(configuration.soundVolume, 0.6)
    }
}
