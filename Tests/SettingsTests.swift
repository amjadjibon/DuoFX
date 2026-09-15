import XCTest
@testable import DuoFX
@testable import DuoFXCore

final class SettingsTests: XCTestCase {
    @MainActor
    func testCustomPresetsPersistAndPreserveCalibrationAndAccessibility() throws {
        let suite = "DuoFXPresets.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.configuration.animationMode = .perspective
        model.configuration.soundEnabled = true
        let id = try XCTUnwrap(model.savePreset(named: "  Evening  "))
        XCTAssertNil(model.savePreset(named: "evening"))
        XCTAssertNil(model.savePreset(named: "   "))
        XCTAssertNil(model.savePreset(named: String(repeating: "a", count: 61)))
        let restored = AppModel(defaults: defaults)
        XCTAssertEqual(restored.customPresets.first?.name, "Evening")
        restored.configuration.applyRecommended()
        restored.configuration.workingAngle = 115
        restored.configuration.minimumAngle = 35
        restored.configuration.soundEnabled = false
        restored.motionPreference = .reduced
        restored.angleSource = .manual
        restored.desktopSource = .testImage
        restored.applyPreset(id: id)
        XCTAssertEqual(restored.configuration.animationMode, .perspective)
        XCTAssertTrue(restored.configuration.soundEnabled)
        XCTAssertEqual(restored.configuration.workingAngle, 115)
        XCTAssertEqual(restored.configuration.minimumAngle, 35)
        XCTAssertEqual(restored.motionPreference, .reduced)
        XCTAssertEqual(restored.angleSource, .manual)
        XCTAssertEqual(restored.desktopSource, .testImage)
        XCTAssertFalse(restored.isEnabled)
        restored.configuration.blurStrength = 7
        restored.updatePreset(id: id)
        let updated = AppModel(defaults: defaults)
        XCTAssertEqual(updated.customPresets.first?.configuration.blurStrength, 7)
        updated.deletePreset(id: id)
        XCTAssertTrue(AppModel(defaults: defaults).customPresets.isEmpty)
        defaults.set(Data("invalid".utf8), forKey: "customPresets")
        XCTAssertTrue(AppModel(defaults: defaults).customPresets.isEmpty)
    }

    @MainActor
    func testMotionPreferenceFollowsSystemAndPersistsOverrides() throws {
        let suite = "DuoFXMotion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        XCTAssertEqual(model.motionPreference, .system)
        XCTAssertFalse(model.liveReduceMotion)
        model.systemReduceMotion = true
        XCTAssertTrue(model.liveReduceMotion)
        model.motionPreference = .full
        XCTAssertFalse(model.liveReduceMotion)
        XCTAssertEqual(AppModel(defaults: defaults).motionPreference, .full)
        model.systemReduceMotion = false
        model.motionPreference = .reduced
        XCTAssertTrue(AppModel(defaults: defaults).liveReduceMotion)
    }

    @MainActor
    func testPreferencesPersistButEffectDoesNotAutoEnable() throws {
        let suite = "DuoFXTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppModel(defaults: defaults)
        XCTAssertEqual(first.desktopSource, .liveDesktop)
        XCTAssertEqual(first.angleSource, .sensor)
        first.configuration.workingAngle = 110
        XCTAssertFalse(first.configuration.soundEnabled)
        first.configuration.soundEnabled = true
        first.configuration.soundVolume = 0.65
        first.configuration.motionResponse = 0.28
        first.configuration.animationMode = .fold
        first.configuration.sweepDirection = .left
        first.configuration.foldShadow = 0.7
        first.configuration.foldWidth = 0.25
        first.configuration.apply(.shade)
        first.angleSource = .sensor; first.desktopSource = .liveDesktop
        first.isEnabled = true
        let second = AppModel(defaults: defaults)
        XCTAssertEqual(second.configuration.workingAngle, 110)
        XCTAssertTrue(second.configuration.soundEnabled)
        XCTAssertEqual(second.configuration.soundVolume, 0.65)
        XCTAssertEqual(second.configuration.motionResponse, 0.28)
        XCTAssertEqual(second.configuration.animationMode, .fold)
        XCTAssertEqual(second.configuration.sweepDirection, .left)
        XCTAssertEqual(second.configuration.foldShadow, 0.7)
        XCTAssertEqual(second.configuration.foldWidth, 0.25)
        XCTAssertEqual(second.configuration.style, .shade)
        XCTAssertEqual(second.angleSource, .sensor)
        XCTAssertEqual(second.desktopSource, .liveDesktop)
        XCTAssertFalse(second.isEnabled)
        defaults.set(Data("invalid".utf8), forKey: "effectConfiguration")
        XCTAssertEqual(AppModel(defaults: defaults).configuration, EffectConfiguration())
    }
    @MainActor
    func testExplicitManualPreviewChoiceSurvivesRelaunch() throws {
        let suite = "DuoFXTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.angleSource = .manual
        model.desktopSource = .testImage
        let restored = AppModel(defaults: defaults)
        XCTAssertEqual(restored.angleSource, .manual)
        XCTAssertEqual(restored.desktopSource, .testImage)
    }

    @MainActor
    func testPerspectiveSettingsPersistAndValidate() throws {
        let suite = "DuoFXTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.configuration.animationMode = .perspective
        model.configuration.perspectiveStrength = 0.8
        model.configuration.perspectiveFeather = 0.12
        let restored = AppModel(defaults: defaults)
        XCTAssertEqual(restored.configuration.animationMode, .perspective)
        XCTAssertEqual(restored.configuration.perspectiveStrength, 0.8)
        XCTAssertEqual(restored.configuration.perspectiveFeather, 0.12)
        var configuration = restored.configuration
        configuration.perspectiveStrength = -1
        XCTAssertEqual(configuration.validated().perspectiveStrength, 0)
        configuration.perspectiveStrength = 2
        XCTAssertEqual(configuration.validated().perspectiveStrength, 1)
        configuration.perspectiveStrength = .nan
        XCTAssertEqual(configuration.validated().perspectiveStrength, 0.55)
        configuration.perspectiveFeather = .nan
        XCTAssertEqual(configuration.validated().perspectiveFeather, 0.06)
        configuration.perspectiveFeather = 1
        XCTAssertEqual(configuration.validated().perspectiveFeather, 0.2)
        configuration.perspectiveFeather = -1
        XCTAssertEqual(configuration.validated().perspectiveFeather, 0)
    }
    @MainActor
    func testUpgradeKeepsCalibrationAndBlurFromFoldingVersion() throws {
        let suite = "DuoFXTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = Data(#"{"style":"shade","workingAngle":115,"minimumAngle":30,"perspective":0.75,"verticalStretch":0.25,"blurStrength":18,"shadowStrength":0.3,"fadeStart":0.72,"viewerDistance":2.5}"#.utf8)
        defaults.set(legacy, forKey: "effectConfiguration")
        let model = AppModel(defaults: defaults)
        XCTAssertEqual(model.configuration.style, .shade)
        XCTAssertEqual(model.configuration.workingAngle, 115)
        XCTAssertEqual(model.configuration.minimumAngle, 30)
        XCTAssertEqual(model.configuration.blurStrength, 18)
        XCTAssertEqual(model.configuration.shadowStrength, 0.3)
        XCTAssertEqual(model.configuration.edgeSoftness, 0.22)
        XCTAssertFalse(model.configuration.soundEnabled)
        XCTAssertEqual(model.configuration.soundVolume, 0.25)
        XCTAssertEqual(model.configuration.motionResponse, 0.20)
        XCTAssertEqual(model.configuration.animationMode, .sweep)
        XCTAssertEqual(model.configuration.sweepDirection, .down)
        XCTAssertEqual(model.configuration.perspectiveStrength, 0.55)
        XCTAssertEqual(model.configuration.perspectiveFeather, 0.06)
        model.configuration.edgeSoftness = 0.2
        XCTAssertEqual(AppModel(defaults: defaults).configuration.edgeSoftness, 0.2)
    }

}
