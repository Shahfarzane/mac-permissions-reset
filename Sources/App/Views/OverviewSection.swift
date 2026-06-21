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

    private struct InfoItem: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var mono: Bool = false
    }

    private var items: [InfoItem] {
        var rows = [InfoItem(label: "Bundle ID", value: report.app.bundleID, mono: true)]
        if let versionText { rows.append(.init(label: "Version", value: versionText, mono: true)) }
        rows.append(.init(label: "Path", value: abbreviateHome(report.app.path), mono: true))
        rows.append(.init(label: "Kind", value: isApple ? "Apple" : "Third-party"))
        if let team = report.signing.teamID { rows.append(.init(label: "Team ID", value: team, mono: true)) }
        if let authority = report.signing.authority { rows.append(.init(label: "Signed by", value: authority)) }
        rows.append(.init(label: "Sandboxed", value: report.signing.isSandboxed ? "Yes" : "No"))
        return rows
    }

    var body: some View {
        SectionCard("Overview", systemImage: "info.circle") {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    row(item)
                }
            }
        }
    }

    private func row(_ item: InfoItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(item.label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)
            Text(item.value)
                .font(item.mono ? .body.monospaced() : .body)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DS.rowPadding)
    }
}
