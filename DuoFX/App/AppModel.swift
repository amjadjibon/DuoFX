import Foundation
import Observation
#if SWIFT_PACKAGE
import DuoFXCore
#endif

@Observable @MainActor
final class AppModel {
    var isEnabled = false
    var configuration: EffectConfiguration { didSet { persist() } }
    var angleSource: AngleSource { didSet { persist() } }
    var desktopSource: DesktopSource { didSet { persist() } }
    var manualAngle = 95.0
    var currentAngle = 95.0
    var velocity = 0.0
    var progress: Float = 0
    var status = "Paused"
    var errorMessage: String?
    var sensorDiagnostic = SensorDiagnostic()
    var isCapturing = false
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "effectConfiguration"),
           let saved = try? JSONDecoder().decode(EffectConfiguration.self, from: data) {
            configuration = saved.validated()
        } else {
            configuration = EffectConfiguration()
        }
        angleSource = AngleSource(rawValue: defaults.string(forKey: "angleSource") ?? "") ?? .manual
        desktopSource = DesktopSource(rawValue: defaults.string(forKey: "desktopSource") ?? "") ?? .testImage
        manualAngle = configuration.workingAngle
        currentAngle = configuration.workingAngle
    }

    func pause() { isEnabled = false }

    private func persist() {
        if let data = try? JSONEncoder().encode(configuration.validated()) {
            defaults.set(data, forKey: "effectConfiguration")
        }
        defaults.set(angleSource.rawValue, forKey: "angleSource")
        defaults.set(desktopSource.rawValue, forKey: "desktopSource")
    }
}
