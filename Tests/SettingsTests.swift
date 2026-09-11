import XCTest
@testable import DuoFX
@testable import DuoFXCore

final class SettingsTests: XCTestCase {
    @MainActor
    func testPreferencesPersistButEffectDoesNotAutoEnable() throws {
        let suite = "DuoFXTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppModel(defaults: defaults)
        XCTAssertEqual(first.desktopSource, .testImage)
        XCTAssertEqual(first.angleSource, .manual)
        first.configuration.workingAngle = 110
        first.configuration.apply(.shade)
        first.angleSource = .sensor; first.desktopSource = .liveDesktop
        first.isEnabled = true
        let second = AppModel(defaults: defaults)
        XCTAssertEqual(second.configuration.workingAngle, 110)
        XCTAssertEqual(second.configuration.style, .shade)
        XCTAssertEqual(second.angleSource, .sensor)
        XCTAssertEqual(second.desktopSource, .liveDesktop)
        XCTAssertFalse(second.isEnabled)
        defaults.set(Data("invalid".utf8), forKey: "effectConfiguration")
        XCTAssertEqual(AppModel(defaults: defaults).configuration, EffectConfiguration())
    }
    @MainActor
    func testManualSensorStopsDeliveringWhenPaused() {
        let sensor = ManualAngleSensor()
        var readings: [Double] = []
        sensor.onReading = { readings.append($0) }
        sensor.start(); sensor.angle = 60; sensor.stop(); sensor.angle = 25
        XCTAssertEqual(readings, [95, 60])
    }
}
