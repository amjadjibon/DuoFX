import Foundation

enum CaptureError: LocalizedError {
    case noBuiltInDisplay, ownApplicationMissing, permissionDenied, stalePermission
    var errorDescription: String? {
        switch self {
        case .noBuiltInDisplay: "No active built-in display found. Open the MacBook lid and try again."
        case .ownApplicationMissing: "DuoFX could not exclude itself from capture. Quit and reopen the app."
        case .permissionDenied: "Allow DuoFX in System Settings → Privacy & Security → Screen Recording, then quit and reopen DuoFX. The bundled image works without permission."
        case .stalePermission: "Screen capture could not start. If you just granted permission, quit and reopen DuoFX."
        }
    }
}
