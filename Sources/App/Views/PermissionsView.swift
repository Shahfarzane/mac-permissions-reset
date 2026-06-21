import SwiftUI
import AppKit
import PermissionFlow
import PermissionFlowStatusStore

/// A permission AppReset itself needs in order to do its job. Backed by a
/// vendored `PermissionFlow` pane so we get live status + the drag-to-grant flow.
struct AppPermission: Identifiable {
    let pane: PermissionFlowPane
    let title: String
    let detail: String
    let systemImage: String
    let required: Bool

    var id: String { pane.rawValue }
}

extension AppPermission {
    /// AppReset's own requirements. Full Disk Access is the one hard requirement
    /// — it's what lets AppReset read the privacy grants other apps have stored
    /// in the protected user TCC database. Everything else degrades gracefully.
    static let appResetRequirements: [AppPermission] = [
        .init(
            pane: .fullDiskAccess,
            title: "Full Disk Access",
            detail: "Lets AppReset read the privacy grants other apps have been given (stored in the protected user TCC database). Listing, declared permissions, data scanning, and resets all work without it.",
            systemImage: "externaldrive.badge.person.crop",
            required: true
        ),
    ]
}

/// AppReset's own "Permissions" panel: every permission the app itself needs,
/// each with live status and a one-click grant flow (opens the right System
/// Settings page and floats a panel to drag AppReset into the list).
struct PermissionsView: View {
    @StateObject private var store = PermissionFlowStatusStore(
        panes: AppPermission.appResetRequirements.map(\.pane)
    )
    @Environment(\.dismiss) private var dismiss

    /// The app bundle the drag-to-grant panel should offer to drop into the list.
    private let suggestedAppURLs = [Bundle.main.bundleURL]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sectionSpacing) {
                    ForEach(AppPermission.appResetRequirements) { permission in
                        permissionRow(permission)
                    }
                    footerNote
                }
                .padding(DS.contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 480, height: 340)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("AppReset Permissions")
                    .font(.title3.weight(.semibold))
                Text("What AppReset itself needs to inspect other apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .loopButton(.plain)
        }
        .padding(DS.contentPadding)
    }

    private func permissionRow(_ permission: AppPermission) -> some View {
        let state = store.state(for: permission.pane)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: permission.systemImage)
                .font(.title2)
                .foregroundStyle(state == .granted ? Color.green : Color.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(permission.title)
                        .font(.body.weight(.semibold))
                    if permission.required {
                        Badge(text: "Required", color: .orange,
                              help: "AppReset can't read other apps' privacy grants without this.")
                    }
                    Spacer(minLength: 8)
                    statusControl(permission, state: state)
                }
                Text(permission.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// A granted badge, a spinner while checking, or the PermissionFlow grant
    /// button (which opens Settings and floats the drag-to-grant panel).
    @ViewBuilder
    private func statusControl(_ permission: AppPermission, state: PermissionAuthorizationState) -> some View {
        switch state {
        case .granted:
            Badge(text: "Granted", color: .green)
        case .checking:
            ProgressView().controlSize(.small)
        case .notGranted, .unknown:
            PermissionFlowButton(pane: permission.pane, suggestedAppURLs: suggestedAppURLs) { _ in
                Text("Grant Access")
            }
            .loopButton(.prominent)
        }
    }

    private var footerNote: some View {
        Label {
            Text("Granting opens the right System Settings page and floats a panel so you can drag AppReset straight into the list — macOS can't grant access programmatically.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
