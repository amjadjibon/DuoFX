import Foundation

public enum EffectStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case silk, shade, frost
    public var id: Self { self }

    public var preset: EffectConfiguration {
        var value = EffectConfiguration()
        value.style = self
        switch self {
        case .silk:
            value.perspective = 0.5; value.blurStrength = 1.5; value.shadowStrength = 0.15
        case .shade:
            value.perspective = 0.6; value.blurStrength = 4; value.shadowStrength = 0.8
        case .frost:
            value.perspective = 0.85; value.blurStrength = 12; value.shadowStrength = 0.4
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
    public var perspective = 0.85
    public var verticalStretch = 0.25
    public var blurStrength = 12.0
    public var shadowStrength = 0.4
    public var fadeStart = 0.72
    public var viewerDistance = 2.5
    public init() {}

    public func validated() -> Self {
        var copy = self
        copy.workingAngle = clamp(workingAngle, 40...140, fallback: 95)
        copy.minimumAngle = clamp(minimumAngle, 0...(copy.workingAngle - 5), fallback: 25)
        copy.perspective = clamp(perspective, 0...1, fallback: 0.85)
        copy.verticalStretch = clamp(verticalStretch, 0...1, fallback: 0.25)
        copy.blurStrength = clamp(blurStrength, 0...30, fallback: 12)
        copy.shadowStrength = clamp(shadowStrength, 0...1, fallback: 0.4)
        copy.fadeStart = clamp(fadeStart, 0.3...0.95, fallback: 0.72)
        copy.viewerDistance = clamp(viewerDistance, 1...6, fallback: 2.5)
        return copy
    }

    public mutating func apply(_ style: EffectStyle) {
        let preset = style.preset
        self.style = style
        perspective = preset.perspective
        blurStrength = preset.blurStrength
        shadowStrength = preset.shadowStrength
    }
}

private func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
    min(max(value.isFinite ? value : fallback, range.lowerBound), range.upperBound)
}
