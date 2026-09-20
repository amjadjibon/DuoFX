import Foundation
import Observation

enum LicenseStatus: Equatable {
    case unlicensed
    case activating
    case licensed
    case invalid(String)
}

/// Talks to Lemon Squeezy's License API (activate/validate/deactivate), which is designed to be
/// called directly from a shipped client: it is keyed by the license key itself, not a store secret.
@Observable @MainActor
final class LicenseManager {
    // Replace with the real Lemon Squeezy product checkout URL once the store/product exist.
    static let purchaseURL = URL(string: "https://duofx.lemonsqueezy.com/buy/replace-with-your-product-id")!
    static let offlineGracePeriod: TimeInterval = 14 * 24 * 60 * 60

    private(set) var status: LicenseStatus
    var licenseKeyInput = ""

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let instanceName: String
    @ObservationIgnored private static let apiBase = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!
    @ObservationIgnored private static let licenseKeyDefaultsKey = "license.key"
    @ObservationIgnored private static let instanceIDDefaultsKey = "license.instanceID"
    @ObservationIgnored private static let lastValidatedDefaultsKey = "license.lastValidatedAt"

    var isLicensed: Bool {
        if case .licensed = status { return true }
        return false
    }

    init(defaults: UserDefaults = .standard, session: URLSession = .shared, instanceName: String = Host.current().localizedName ?? "Mac") {
        self.defaults = defaults
        self.session = session
        self.instanceName = instanceName
        status = defaults.string(forKey: Self.licenseKeyDefaultsKey) != nil ? .licensed : .unlicensed
    }

    /// Re-checks a cached activation against Lemon Squeezy. Call once at launch; stays silently
    /// licensed offline within the grace period so normal use never depends on connectivity.
    func revalidateIfNeeded() async {
        guard let key = defaults.string(forKey: Self.licenseKeyDefaultsKey),
              let instanceID = defaults.string(forKey: Self.instanceIDDefaultsKey) else { return }
        do {
            let valid = try await callAPI(path: "validate", body: ["license_key": key, "instance_id": instanceID], as: ValidateResponse.self).valid
            if valid {
                defaults.set(Date().timeIntervalSince1970, forKey: Self.lastValidatedDefaultsKey)
                status = .licensed
            } else {
                clearLocalLicense()
                status = .invalid("This license is no longer active. Purchases and refunds are handled by Lemon Squeezy.")
            }
        } catch {
            let lastValidated = defaults.double(forKey: Self.lastValidatedDefaultsKey)
            let withinGrace = lastValidated > 0 && Date().timeIntervalSince1970 - lastValidated < Self.offlineGracePeriod
            status = withinGrace ? .licensed : .invalid("Couldn't reach the license server to confirm your license. Reconnect and reopen DuoFX.")
        }
    }

    func activate() async {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        status = .activating
        do {
            let response = try await callAPI(path: "activate", body: ["license_key": key, "instance_name": instanceName], as: ActivateResponse.self)
            guard response.activated == true, let instance = response.instance else {
                status = .invalid(response.error ?? "This license key isn't valid.")
                return
            }
            defaults.set(key, forKey: Self.licenseKeyDefaultsKey)
            defaults.set(instance.id, forKey: Self.instanceIDDefaultsKey)
            defaults.set(Date().timeIntervalSince1970, forKey: Self.lastValidatedDefaultsKey)
            licenseKeyInput = ""
            status = .licensed
        } catch {
            status = .invalid("Couldn't reach the license server. Check your connection and try again.")
        }
    }

    func deactivate() async {
        if let key = defaults.string(forKey: Self.licenseKeyDefaultsKey),
           let instanceID = defaults.string(forKey: Self.instanceIDDefaultsKey) {
            _ = try? await callAPI(path: "deactivate", body: ["license_key": key, "instance_id": instanceID], as: DeactivateResponse.self)
        }
        clearLocalLicense()
        status = .unlicensed
    }

    private func clearLocalLicense() {
        defaults.removeObject(forKey: Self.licenseKeyDefaultsKey)
        defaults.removeObject(forKey: Self.instanceIDDefaultsKey)
        defaults.removeObject(forKey: Self.lastValidatedDefaultsKey)
    }

    private func callAPI<Response: Decodable>(path: String, body: [String: String], as type: Response.Type) async throws -> Response {
        var request = URLRequest(url: Self.apiBase.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct ActivateResponse: Decodable {
    let activated: Bool?
    let error: String?
    let instance: Instance?
    struct Instance: Decodable { let id: String }
}

private struct ValidateResponse: Decodable {
    let valid: Bool
    let error: String?
}

private struct DeactivateResponse: Decodable {
    let deactivated: Bool?
}
