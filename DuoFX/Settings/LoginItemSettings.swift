import AppKit
import ServiceManagement
import SwiftUI

struct LoginItemSettings: View {
    @State private var status = SMAppService.mainApp.status
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: Binding(
                get: { status == .enabled || status == .requiresApproval },
                set: { setEnabled($0) }
            ))
            .disabled(isUpdating)
            Text("Opens DuoFX in the menu bar after you sign in. Effects start paused.")
                .font(.caption).foregroundStyle(.secondary)
            if status == .requiresApproval {
                Text("Allow DuoFX in Login Items to finish enabling launch at login.")
                    .font(.caption)
                Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .onAppear { status = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
    }

    private func setEnabled(_ enabled: Bool) {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        Task { @MainActor in
            defer {
                status = SMAppService.mainApp.status
                isUpdating = false
            }
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try await SMAppService.mainApp.unregister()
                }
            } catch {
                errorMessage = "Could not change launch at login: \(error.localizedDescription)"
            }
        }
    }
}
