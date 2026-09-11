import Foundation

enum CaptureError: LocalizedError {
    case noBuiltInDisplay, ownApplicationMissing, permissionDenied, stalePermission
    var errorDescription: String? {
        switch self {
        case .noBuiltInDisplay: "No active built-in display found. Open the MacBook lid and try again."
        case .ownApplicationMissing: "DuoFX could not exclude itself from capture. Quit and reopen the app."
        case .permissionDenied: "Screen Recording access is unavailable for this copy of DuoFX. If DuoFX is already enabled in System Settings, quit it, remove the old entry, add \(Bundle.main.bundlePath) again, enable access, then reopen DuoFX."
        case .stalePermission: "Screen capture could not start. If you just granted permission, quit and reopen DuoFX."
        }
    }
}
