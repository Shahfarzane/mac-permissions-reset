import SwiftUI
import AppResetKit

struct DeclaredPermissionsSection: View {
    let report: AppReport
    @State private var expanded = false

    private let previewCount = 8

    private var visible: [DeclaredPermission] {
        (expanded || report.declared.count <= previewCount)
            ? report.declared
            : Array(report.declared.prefix(previewCount))
    }

    var body: some View {
        SectionCard("Declared Permissions", systemImage: "checklist", subtitle: "\(report.declared.count)") {
            if report.declared.isEmpty {
                Text("This app declares no special permissions or capabilities.")
                    .foregroundStyle(.secondary)
                    .font(.body)
            } else {
                HStack(spacing: 10) {
                    Badge(text: "Info.plist", color: .blue)
                    Badge(text: "Entitlement", color: .purple)
                    Badge(text: "TCC Allow", color: .teal)
                    Text("How the permission is declared")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 4)

                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, permission in
                        if index > 0 { Divider() }
                        PermissionRow(permission: permission)
                    }
                }
                if report.declared.count > previewCount {
                    Button(expanded ? "Show less" : "Show all \(report.declared.count)") {
                        expanded.toggle()
                    }
                    .loopButton(.plain, size: .compact)
                    .padding(.top, 8)
                }
            }
        }
    }
}

private struct PermissionRow: View {
    let permission: DeclaredPermission

    private var sourceBadge: (text: String, color: Color, help: String) {
        switch permission.source {
        case .usageDescription:
            return ("Info.plist", .blue,
                    "Backed by an Info.plist usage-description string (e.g. NSCameraUsageDescription) — the prompt text the app shows when it asks for access.")
        case .entitlement:
            return ("Entitlement", .purple,
                    "Backed by a code-signing entitlement (com.apple.security.*) baked into the app at build time.")
        case .tccAllow:
            return ("TCC Allow", .teal,
                    "A private TCC allow declaration (com.apple.private.tcc.allow) — Apple apps pre-authorized for this service.")
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.friendlyName)
                    .font(.body)
                if let detail = permission.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Badge(text: sourceBadge.text, color: sourceBadge.color, help: sourceBadge.help)
        }
        .padding(.vertical, DS.rowPadding)
    }
}
