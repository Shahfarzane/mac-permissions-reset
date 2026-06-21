import SwiftUI
import AppResetKit

/// Drives the sidebar: loads installed apps, search filtering, grouping into
/// developer vs system apps, and the Full Disk Access state for the banner.
@MainActor
@Observable
final class AppListModel {
    private let service = AppResetService()

    var apps: [AppInfo] = []          // all apps (developer + system)
    var search: String = ""
    var showSystem: Bool = false      // whether the System group is shown
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

    /// Apple / system apps — shown second, only when `showSystem` or actively searching.
    var systemApps: [AppInfo] {
        apps.filter { isSystem($0) && matchesSearch($0) }
    }

    /// While searching, reveal system matches even if the System group is collapsed.
    var systemGroupVisible: Bool {
        showSystem || !search.isEmpty
    }

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
