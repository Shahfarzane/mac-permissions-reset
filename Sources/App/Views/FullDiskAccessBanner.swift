import SwiftUI
import AppKit

/// Setup banner shown when AppReset itself lacks Full Disk Access. This is about
/// the tool's own access (required to read the user TCC database) — not a
/// third-party app's permission — so deep-linking to Settings is appropriate.
struct FullDiskAccessBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Full Disk Access needed", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
            Text("Grant AppReset Full Disk Access to read per-app privacy grants. Listing, declared permissions, data scanning, and resets all work without it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Privacy Settings…") { openFullDiskAccessSettings() }
                .controlSize(.small)
                .buttonStyle(.glass)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
