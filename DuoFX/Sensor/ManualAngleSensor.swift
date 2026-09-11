import Foundation

@MainActor
final class ManualAngleSensor: LidAngleProviding {
    var angle = 95.0 { didSet { if running { onReading?(angle) } } }
    var isAvailable: Bool { true }
    var onReading: ((Double) -> Void)?
    private var running = false
    func start() { running = true; onReading?(angle) }
    func stop() { running = false }
}
