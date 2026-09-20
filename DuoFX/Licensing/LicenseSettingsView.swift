import AppKit
import SwiftUI

struct LicenseSettingsView: View {
    @Bindable var license: LicenseManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch license.status {
            case .licensed:
                Label("Licensed on this Mac", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Thanks for supporting DuoFX.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Deactivate this Mac…", role: .destructive) {
                    Task { await license.deactivate() }
                }
            case .activating:
                ProgressView("Activating…")
            case .unlicensed, .invalid:
                Text("A one-time purchase activates DuoFX on this Mac.")
                    .font(.callout)
                Button("Buy a license…") { NSWorkspace.shared.open(LicenseManager.purchaseURL) }
                HStack {
                    TextField("License key", text: $license.licenseKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await license.activate() } }
                    Button("Activate") { Task { await license.activate() } }
                        .disabled(license.licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if case .invalid(let message) = license.status {
                    Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
    }
}
