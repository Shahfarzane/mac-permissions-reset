import SwiftUI
import AppResetKit

struct TCCSection: View {
    let report: AppReport
    let fullDiskAccess: Bool
    let isResetting: Bool
    let onResetService: (String) -> Void
    let onResetAll: () -> Void

    var body: some View {
        SectionCard(
            "Privacy Permissions",
            systemImage: "hand.raised",
            subtitle: "\(report.grants.count)",
            headerAccessory: report.grants.isEmpty ? nil : AnyView(
                Button("Reset All", action: onResetAll)
                    .resetButtonStyle()
                    .focusable(false)
                    .disabled(isResetting)
            )
        ) {
            if report.grants.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No privacy records for this app.")
                        .foregroundStyle(.secondary)
                        .font(.body)
                    if !fullDiskAccess {
                        Text("Grant Full Disk Access to read grants stored in the user database.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(report.grants.enumerated()), id: \.element.id) { index, grant in
                        if index > 0 { Divider() }
                        grantRow(grant)
                    }
                }
                Text("Resetting clears the decision so the app asks again next launch. macOS doesn't allow granting another app's permission programmatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }

    private func grantRow(_ grant: TCCGrant) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(grant.friendlyName)
                    .font(.body)
                Text("\(grant.service) • \(grant.sourceDB.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Badge(text: grant.state.label, color: stateColor(grant.state))
            Button("Reset") { onResetService(grant.service) }
                .resetButtonStyle()
                .focusable(false)
                .disabled(isResetting)
        }
        .padding(.vertical, DS.rowPadding)
    }
}
