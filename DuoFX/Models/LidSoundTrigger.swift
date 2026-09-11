import Foundation

public enum LidSound: String, Sendable { case opening = "Open", closing = "Close" }

/// One cue per direction, with a travel threshold to reject sensor jitter.
public struct LidSoundTrigger {
    private var extreme: Double?
    private var direction: LidSound?
    private var lastCue = -Double.infinity
    public init() {}

    public mutating func update(progress: Double, at time: TimeInterval) -> LidSound? {
        guard progress.isFinite, time.isFinite else { return nil }
        let progress = min(max(progress, 0), 1)
        guard let previous = extreme else { extreme = progress; return nil }
        let delta = progress - previous
        let candidate: LidSound = delta > 0 ? .closing : .opening
        if candidate == direction {
            extreme = progress
            return nil
        }
        // Require 3% of the sweep in a new direction and limit rapid reversals.
        guard abs(delta) >= 0.03, time - lastCue >= 0.3 else { return nil }
        direction = candidate; extreme = progress; lastCue = time
        return candidate
    }
}
