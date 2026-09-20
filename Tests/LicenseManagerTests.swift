import XCTest
@testable import DuoFX

/// Stubs Lemon Squeezy's License API so tests never touch the network.
private final class StubURLProtocol: URLProtocol {
    static var handler: (@Sendable (URLRequest) -> (Int, [String: Any]?))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, json) = Self.handler?(request) ?? (500, nil)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let json, let data = try? JSONSerialization.data(withJSONObject: json) {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class LicenseManagerTests: XCTestCase {
    private func makeManager(suite: String) throws -> LicenseManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return LicenseManager(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)),
                               session: URLSession(configuration: configuration),
                               instanceName: "Test Mac")
    }

    func testActivateSucceedsAndPersists() async throws {
        let suite = "DuoFXLicenseActivate.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = try makeManager(suite: suite)
        StubURLProtocol.handler = { _ in
            (200, ["activated": true, "instance": ["id": "instance-1"]])
        }
        manager.licenseKeyInput = "  VALID-KEY  "
        await manager.activate()
        XCTAssertEqual(manager.status, .licensed)
        XCTAssertTrue(manager.isLicensed)
        XCTAssertEqual(manager.licenseKeyInput, "")
        XCTAssertEqual(defaults.string(forKey: "license.key"), "VALID-KEY")
        XCTAssertEqual(defaults.string(forKey: "license.instanceID"), "instance-1")
    }

    func testActivateRejectsInvalidKey() async throws {
        let suite = "DuoFXLicenseInvalid.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let manager = try makeManager(suite: suite)
        StubURLProtocol.handler = { _ in
            (200, ["activated": false, "error": "This license key isn't valid."])
        }
        manager.licenseKeyInput = "BAD-KEY"
        await manager.activate()
        XCTAssertEqual(manager.status, .invalid("This license key isn't valid."))
        XCTAssertFalse(manager.isLicensed)
    }

    func testActivateHandlesNetworkFailure() async throws {
        let suite = "DuoFXLicenseNetworkFail.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let manager = try makeManager(suite: suite)
        StubURLProtocol.handler = { _ in (500, nil) }
        manager.licenseKeyInput = "SOME-KEY"
        await manager.activate()
        guard case .invalid = manager.status else { return XCTFail("Expected .invalid, got \(manager.status)") }
    }

    func testRevalidateKeepsValidLicenseAndUpdatesTimestamp() async throws {
        let suite = "DuoFXLicenseRevalidate.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("KEY", forKey: "license.key")
        defaults.set("instance-1", forKey: "license.instanceID")
        let manager = try makeManager(suite: suite)
        XCTAssertTrue(manager.isLicensed, "cached activation should be optimistic before revalidation")
        StubURLProtocol.handler = { _ in (200, ["valid": true]) }
        await manager.revalidateIfNeeded()
        XCTAssertTrue(manager.isLicensed)
        XCTAssertGreaterThan(defaults.double(forKey: "license.lastValidatedAt"), 0)
    }

    func testRevalidateClearsRevokedLicense() async throws {
        let suite = "DuoFXLicenseRevoked.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("KEY", forKey: "license.key")
        defaults.set("instance-1", forKey: "license.instanceID")
        let manager = try makeManager(suite: suite)
        StubURLProtocol.handler = { _ in (200, ["valid": false]) }
        await manager.revalidateIfNeeded()
        XCTAssertFalse(manager.isLicensed)
        XCTAssertNil(defaults.string(forKey: "license.key"))
    }

    func testRevalidateHonorsOfflineGracePeriod() async throws {
        let suite = "DuoFXLicenseGrace.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("KEY", forKey: "license.key")
        defaults.set("instance-1", forKey: "license.instanceID")
        defaults.set(Date().timeIntervalSince1970, forKey: "license.lastValidatedAt")
        let manager = try makeManager(suite: suite)
        StubURLProtocol.handler = { _ in (500, nil) }
        await manager.revalidateIfNeeded()
        XCTAssertTrue(manager.isLicensed, "a recently-validated license should stay active while offline")
    }

    func testRevalidateExpiresAfterGracePeriod() async throws {
        let suite = "DuoFXLicenseGraceExpired.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("KEY", forKey: "license.key")
        defaults.set("instance-1", forKey: "license.instanceID")
        defaults.set(Date().timeIntervalSince1970 - LicenseManager.offlineGracePeriod - 1, forKey: "license.lastValidatedAt")
        let manager = try makeManager(suite: suite)
        StubURLProtocol.handler = { _ in (500, nil) }
        await manager.revalidateIfNeeded()
        XCTAssertFalse(manager.isLicensed)
    }

    func testDeactivateClearsLocalState() async throws {
        let suite = "DuoFXLicenseDeactivate.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("KEY", forKey: "license.key")
        defaults.set("instance-1", forKey: "license.instanceID")
        let manager = try makeManager(suite: suite)
        StubURLProtocol.handler = { _ in (200, ["deactivated": true]) }
        await manager.deactivate()
        XCTAssertFalse(manager.isLicensed)
        XCTAssertNil(defaults.string(forKey: "license.key"))
        XCTAssertNil(defaults.string(forKey: "license.instanceID"))
    }
}
