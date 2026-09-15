import Foundation
import Observation
#if SWIFT_PACKAGE
import DuoFXCore
#endif

enum MotionPreference: String, CaseIterable, Identifiable {
    case system, reduced, full
    var id: Self { self }
    var title: String {
        switch self {
        case .system: "Follow macOS"
        case .reduced: "Always reduce motion"
        case .full: "Full animation"
        }
    }
}

struct CustomPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var configuration: EffectConfiguration
}

@Observable @MainActor
final class AppModel {
    var isEnabled = false
    var configuration: EffectConfiguration { didSet { persist() } }
    var angleSource: AngleSource { didSet { persist() } }
    var desktopSource: DesktopSource { didSet { persist() } }
    var motionPreference: MotionPreference {
        didSet { defaults.set(motionPreference.rawValue, forKey: "motionPreference") }
    }
    var systemReduceMotion = false
    var liveReduceMotion: Bool {
        motionPreference == .reduced || (motionPreference == .system && systemReduceMotion)
    }
    private(set) var customPresets: [CustomPreset] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(customPresets) {
                defaults.set(data, forKey: "customPresets")
            }
        }
    }
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
        angleSource = AngleSource(rawValue: defaults.string(forKey: "angleSource") ?? "") ?? .sensor
        desktopSource = DesktopSource(rawValue: defaults.string(forKey: "desktopSource") ?? "") ?? .liveDesktop
        motionPreference = MotionPreference(rawValue: defaults.string(forKey: "motionPreference") ?? "") ?? .system
        if let data = defaults.data(forKey: "customPresets"),
           let saved = try? JSONDecoder().decode([CustomPreset].self, from: data) {
            customPresets = saved.map {
                CustomPreset(id: $0.id, name: $0.name, configuration: $0.configuration.validated())
            }
        }
        manualAngle = configuration.workingAngle
        currentAngle = configuration.workingAngle
    }

    func pause() { isEnabled = false }

    func canSavePreset(named name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 60 && !customPresets.contains {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    @discardableResult
    func savePreset(named name: String) -> UUID? {
        guard canSavePreset(named: name) else { return nil }
        let preset = CustomPreset(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  configuration: configuration.validated())
        customPresets.append(preset)
        return preset.id
    }

    func applyPreset(id: UUID) {
        guard let preset = customPresets.first(where: { $0.id == id }) else { return }
        var saved = preset.configuration
        saved.workingAngle = configuration.workingAngle
        saved.minimumAngle = configuration.minimumAngle
        configuration = saved.validated()
    }

    func updatePreset(id: UUID) {
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else { return }
        customPresets[index].configuration = configuration.validated()
    }

    func deletePreset(id: UUID) {
        customPresets.removeAll { $0.id == id }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(configuration.validated()) {
            defaults.set(data, forKey: "effectConfiguration")
        }
        defaults.set(angleSource.rawValue, forKey: "angleSource")
        defaults.set(desktopSource.rawValue, forKey: "desktopSource")
    }
}
