import AppKit
import SwiftUI

@main
struct DuoFXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra {
            MenuView(model: delegate.model, coordinator: delegate.coordinator)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("DuoFX")
        }
        .menuBarExtraStyle(.menu)
        Settings { SettingsView(model: delegate.model) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    lazy var coordinator = EffectCoordinator(model: model)
    private var terminating = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        coordinator.start()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            await coordinator.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

private struct MenuView: View {
    @Environment(\.openSettings) private var openSettings
    @Bindable var model: AppModel
    let coordinator: EffectCoordinator
    var body: some View {
        Text("DuoFX · \(model.status)")
        Toggle("Enable effect", isOn: $model.isEnabled)
        Button("Pause all effects") { coordinator.pause() }
            .keyboardShortcut(".", modifiers: [.command])
        if let message = model.errorMessage { Text(message) }
        Divider()
        Button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Label("Settings…", systemImage: "gear")
        }
            .keyboardShortcut(",")
        Divider()
        Button("Quit DuoFX") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
