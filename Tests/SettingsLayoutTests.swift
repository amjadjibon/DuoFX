import AppKit
import SwiftUI
import XCTest
@testable import DuoFX

final class SettingsLayoutTests: XCTestCase {
    @MainActor
    func testSettingsRenderAtMinimumSizeInLightAndDark() async throws {
        guard let directory = ProcessInfo.processInfo.environment["DUOFX_SETTINGS_SNAPSHOTS"] else {
            throw XCTSkip("Opt in with DUOFX_SETTINGS_SNAPSHOTS to render Settings layout artifacts")
        }
        _ = NSApplication.shared
        let suite = "DuoFXLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        for dark in [false, true] {
            let root = SettingsView(model: model, previewSound: { _ in })
                .environment(\.colorScheme, dark ? .dark : .light)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 670),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 900, height: 670)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let url = URL(fileURLWithPath: directory).appendingPathComponent(dark ? "settings-dark.png" : "settings-light.png")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
            XCTAssertEqual(host.bounds.width, 900)
            XCTAssertEqual(host.bounds.height, 670)
            XCTAssertFalse(model.isEnabled, "Rendering a preview must not enable the desktop effect")
            window.close()
        }
    }
}
