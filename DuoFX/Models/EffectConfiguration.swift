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

public enum AnimationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case sweep, fold, perspective
    public var id: Self { self }
}

public enum SweepDirection: String, CaseIterable, Identifiable, Codable, Sendable {
    case down, up, right, left
    public var id: Self { self }
    public var title: String {
        switch self {
        case .down: "Top to bottom"
        case .up: "Bottom to top"
        case .right: "Left to right"
        case .left: "Right to left"
        }
    }
    public var shaderValue: UInt32 {
        switch self { case .down: 0; case .up: 1; case .right: 2; case .left: 3 }
    }
}

public struct EffectConfiguration: Codable, Equatable, Sendable {
    public var style: EffectStyle = .frost
    public var workingAngle = 95.0
    public var minimumAngle = 25.0
    public var edgeSoftness = 0.22
    public var blurStrength = 18.0
    public var shadowStrength = 0.18
    public var motionResponse = 0.20
    public var animationMode: AnimationMode = .sweep
    public var sweepDirection: SweepDirection = .down
    public var foldShadow = 0.55
    public var foldWidth = 0.18
    public var perspectiveStrength = 0.55
    public var perspectiveFeather = 0.06
    public var soundEnabled = false
    public var soundVolume = 0.25
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case style, workingAngle, minimumAngle, edgeSoftness, blurStrength, shadowStrength
        case soundEnabled, soundVolume, motionResponse
        case animationMode, sweepDirection, foldShadow, foldWidth, perspectiveStrength, perspectiveFeather
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
        animationMode = try values.decodeIfPresent(AnimationMode.self, forKey: .animationMode) ?? .sweep
        sweepDirection = try values.decodeIfPresent(SweepDirection.self, forKey: .sweepDirection) ?? .down
        foldShadow = try values.decodeIfPresent(Double.self, forKey: .foldShadow) ?? 0.55
        foldWidth = try values.decodeIfPresent(Double.self, forKey: .foldWidth) ?? 0.18
        perspectiveStrength = try values.decodeIfPresent(Double.self, forKey: .perspectiveStrength) ?? 0.55
        perspectiveFeather = try values.decodeIfPresent(Double.self, forKey: .perspectiveFeather) ?? 0.06
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
        copy.foldShadow = clamp(foldShadow, 0...1, fallback: 0.55)
        copy.foldWidth = clamp(foldWidth, 0.04...0.35, fallback: 0.18)
        copy.perspectiveStrength = clamp(perspectiveStrength, 0...1, fallback: 0.55)
        copy.perspectiveFeather = clamp(perspectiveFeather, 0...0.2, fallback: 0.06)
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
        animationMode = .sweep; sweepDirection = .down
        motionResponse = 0.20
        soundVolume = 0.25
    }

    public mutating func applyFoldReference() {
        apply(.frost)
        animationMode = .fold; sweepDirection = .down
        blurStrength = 30; edgeSoftness = 0.20; shadowStrength = 0
        foldShadow = 0.70; foldWidth = 0.24; motionResponse = 0.28
    }
}

private func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
    min(max(value.isFinite ? value : fallback, range.lowerBound), range.upperBound)
}
