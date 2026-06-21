import SwiftUI
import AppResetKit

/// Which apps the sidebar shows. Replaces the old Apple-only toggle with an
/// explicit three-way filter the user picks from a dropdown.
enum AppFilter: String, CaseIterable, Identifiable {
    case developer   // third-party apps only (not Apple / not in /System)
    case all         // everything
    case system      // Apple / system apps only

    var id: String { rawValue }

    var label: String {
        switch self {
        case .developer: "Installed Apps"
        case .all: "All Apps"
        case .system: "System Apps"
        }
    }

    var systemImage: String {
        switch self {
        case .developer: "shippingbox"
        case .all: "square.grid.2x2"
        case .system: "apple.logo"
        }
    }
}

/// Drives the sidebar: loads installed apps, search filtering, grouping into
/// developer vs system apps, and the Full Disk Access state for the banner.
@MainActor
@Observable
final class AppListModel {
    private let service = AppResetService()

    var apps: [AppInfo] = []          // all apps (developer + system)
    var search: String = ""
    var filter: AppFilter = .developer   // which group(s) the sidebar shows
    var isLoading = false
    var hasFullDiskAccess = false

    /// Apple/system apps live in /System or use a com.apple.* identifier.
    private func isSystem(_ app: AppInfo) -> Bool {
        app.isAppleSystem || app.bundleID.hasPrefix("com.apple.")
    }

    private func matchesSearch(_ app: AppInfo) -> Bool {
        guard !search.isEmpty else { return true }
        return app.name.localizedCaseInsensitiveContains(search)
            || app.bundleID.localizedCaseInsensitiveContains(search)
    }

    /// Developer-signed (non-Apple) apps — shown first.
    var developerApps: [AppInfo] {
        apps.filter { !isSystem($0) && matchesSearch($0) }
    }

    /// Apple / system apps — shown for the System and All filters.
    var systemApps: [AppInfo] {
        apps.filter { isSystem($0) && matchesSearch($0) }
    }

    /// The Developer group shows for the Developer and All filters.
    var showsDeveloperSection: Bool { filter != .system }

    /// The System group shows for the System and All filters.
    var showsSystemSection: Bool { filter != .developer }

    func app(for id: AppInfo.ID?) -> AppInfo? {
        guard let id else { return nil }
        return apps.first { $0.id == id }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        hasFullDiskAccess = service.hasFullDiskAccess()
        apps = await service.listApps(includeSystem: true)
    }
}
