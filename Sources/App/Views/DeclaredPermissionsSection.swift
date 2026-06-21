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
                    .font(.callout)
            } else {
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
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.tint)
                    .focusable(false)
                    .padding(.top, 8)
                }
            }
        }
    }
}

private struct PermissionRow: View {
    let permission: DeclaredPermission

    private var sourceBadge: (text: String, color: Color) {
        switch permission.source {
        case .usageDescription: return ("Usage", .blue)
        case .entitlement: return ("Entitlement", .purple)
        case .tccAllow: return ("Declared", .teal)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.friendlyName)
                    .font(.callout)
                if let detail = permission.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Badge(text: sourceBadge.text, color: sourceBadge.color)
        }
        .padding(.vertical, 6)
    }
}
