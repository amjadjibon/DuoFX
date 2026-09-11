import Foundation

@MainActor
protocol LidAngleProviding: AnyObject {
    var angle: Double { get }
    var isAvailable: Bool { get }
    var onReading: ((Double) -> Void)? { get set }
    func start()
    func stop()
}
