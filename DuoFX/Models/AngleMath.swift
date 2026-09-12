import Foundation

public func closingProgress(angle: Double, workingAngle: Double, minimumAngle: Double) -> Float {
    guard angle.isFinite, workingAngle.isFinite, minimumAngle.isFinite else { return 0 }
    return Float(min(max((workingAngle - angle) / max(workingAngle - minimumAngle, 1), 0), 1))
}

public func smoothstep(_ low: Float, _ high: Float, _ value: Float) -> Float {
    let x = min(max((value - low) / max(high - low, 0.0001), 0), 1)
    return x * x * (3 - 2 * x)
}

/// Coverage at a normalized vertical coordinate: zero is the top of the display.
public func blurCoverage(y: Float, progress: Float, edgeSoftness: Float) -> Float {
    guard y.isFinite, progress.isFinite, edgeSoftness.isFinite else { return 0 }
    let p = min(max(progress, 0), 1)
    let feather = min(max(edgeSoftness, 0.02), 0.3)
    let boundary = -feather + (1 + 2 * feather) * p
    return 1 - smoothstep(boundary - feather, boundary + feather, min(max(y, 0), 1))
}

public struct AngleSmoother {
    public private(set) var angle: Double?
    public private(set) var velocity = 0.0
    private var timestamp: TimeInterval?
    public init() {}

    @discardableResult
    public mutating func update(_ raw: Double, at time: TimeInterval, response: Double = 0.20) -> Double {
        guard raw.isFinite, time.isFinite else { return angle ?? 95 }
        guard let previous = angle, let last = timestamp, time > last, time - last < 1 else {
            angle = raw; timestamp = time; velocity = 0
            return raw
        }
        // Exact critically damped response: continuous velocity at starts and
        // reversals, independent of whether the display runs at 60 or 120 Hz.
        let dt = time - last
        let duration = min(max(response.isFinite ? response : 0.20, 0.08), 0.4)
        let omega = 2 / duration
        let offset = previous - raw
        let term = velocity + omega * offset
        let decay = exp(-omega * dt)
        var next = raw + (offset + term * dt) * decay
        velocity = (velocity - omega * term * dt) * decay
        // Momentum must never carry the blur beyond its target after reversal.
        if (raw - previous) * (next - raw) > 0 {
            next = raw; velocity = 0
        }
        angle = next; timestamp = time
        return next
    }
}

public struct VisibilityGate {
    public private(set) var isVisible = false
    public init() {}
    @discardableResult
    public mutating func update(angle: Double, workingAngle: Double) -> Bool {
        guard angle.isFinite, workingAngle.isFinite else { isVisible = false; return false }
        // Enter two degrees below calibration, leave half a degree below it.
        isVisible = isVisible ? angle < workingAngle - 0.5 : angle < workingAngle - 2
        return isVisible
    }
}

public enum LidReport {
    /// Apple 05ac:8104, sensor page 0x20, orientation usage 0x8a, feature report 1.
    public static func decode(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 3, bytes.count <= 8, bytes[0] == 1 else { return nil }
        let angle = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
        guard angle <= 180 else { return nil }
        return Double(angle)
    }
}
