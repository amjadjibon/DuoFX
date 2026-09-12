import Foundation

public enum EffectStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case silk, shade, frost
    public var id: Self { self }

    public var preset: EffectConfiguration {
        var value = EffectConfiguration()
        value.style = self
        switch self {
        case .silk:
            value.edgeSoftness = 0.08; value.blurStrength = 1.5; value.shadowStrength = 0.15
        case .shade:
            value.edgeSoftness = 0.10; value.blurStrength = 4; value.shadowStrength = 0.8
        case .frost:
            value.edgeSoftness = 0.22; value.blurStrength = 18; value.shadowStrength = 0.18
        }
        return value
    }
}

public enum AngleSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case manual, sensor
    public var id: Self { self }
}

public enum DesktopSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case testImage, liveDesktop
    public var id: Self { self }
}

public struct EffectConfiguration: Codable, Equatable, Sendable {
    public var style: EffectStyle = .frost
    public var workingAngle = 95.0
    public var minimumAngle = 25.0
    public var edgeSoftness = 0.22
    public var blurStrength = 18.0
    public var shadowStrength = 0.18
    public var motionResponse = 0.20
    public var soundEnabled = false
    public var soundVolume = 0.25
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case style, workingAngle, minimumAngle, edgeSoftness, blurStrength, shadowStrength
        case soundEnabled, soundVolume, motionResponse
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        style = try values.decodeIfPresent(EffectStyle.self, forKey: .style) ?? .frost
        workingAngle = try values.decodeIfPresent(Double.self, forKey: .workingAngle) ?? 95
        minimumAngle = try values.decodeIfPresent(Double.self, forKey: .minimumAngle) ?? 25
        // Older installations have folding parameters but no blur-edge setting.
        // Keep their calibration and appearance instead of resetting all preferences.
        edgeSoftness = try values.decodeIfPresent(Double.self, forKey: .edgeSoftness) ?? 0.22
        blurStrength = try values.decodeIfPresent(Double.self, forKey: .blurStrength) ?? 18
        shadowStrength = try values.decodeIfPresent(Double.self, forKey: .shadowStrength) ?? 0.18
        motionResponse = try values.decodeIfPresent(Double.self, forKey: .motionResponse) ?? 0.20
        soundEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? false
        soundVolume = try values.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.25
    }

    public func validated() -> Self {
        var copy = self
        copy.workingAngle = clamp(workingAngle, 40...140, fallback: 95)
        copy.minimumAngle = clamp(minimumAngle, 0...(copy.workingAngle - 5), fallback: 25)
        copy.edgeSoftness = clamp(edgeSoftness, 0.02...0.3, fallback: 0.22)
        copy.blurStrength = clamp(blurStrength, 0...30, fallback: 18)
        copy.shadowStrength = clamp(shadowStrength, 0...1, fallback: 0.18)
        copy.soundVolume = clamp(soundVolume, 0...1, fallback: 0.25)
        copy.motionResponse = clamp(motionResponse, 0.08...0.4, fallback: 0.20)
        return copy
    }

    public mutating func apply(_ style: EffectStyle) {
        let preset = style.preset
        self.style = style
        edgeSoftness = preset.edgeSoftness
        blurStrength = preset.blurStrength
        shadowStrength = preset.shadowStrength
    }

    public mutating func applyRecommended() {
        apply(.frost)
        motionResponse = 0.20
        soundVolume = 0.25
    }
}

private func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
    min(max(value.isFinite ? value : fallback, range.lowerBound), range.upperBound)
}
