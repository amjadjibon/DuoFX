import Foundation

struct SensorDiagnostic {
    var model: String = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown Mac" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "Unknown Mac" }
        return String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
    }()
    var message = "Select Lid sensor and enable the effect to check this Mac."
    var properties = "Expected: Apple 05ac:8104 · usage 0020:008a · report 1"
    var isAvailable = false
}
