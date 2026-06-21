import SwiftUI
import AppResetKit

struct OverviewSection: View {
    let report: AppReport

    private var isApple: Bool {
        report.app.isAppleSystem || report.app.bundleID.hasPrefix("com.apple.")
    }

    private var versionText: String? {
        let parts = [report.app.version, report.app.build.map { "(\($0))" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var body: some View {
        SectionCard("Overview", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                row("Bundle ID", report.app.bundleID, mono: true)
                if let versionText { row("Version", versionText) }
                row("Path", abbreviateHome(report.app.path), mono: true)
                row("Kind", isApple ? "Apple" : "Third-party")
                if let team = report.signing.teamID { row("Team ID", team, mono: true) }
                if let authority = report.signing.authority { row("Signed by", authority) }
                row("Sandboxed", report.signing.isSandboxed ? "Yes" : "No")
            }
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(mono ? .callout.monospaced() : .callout)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
