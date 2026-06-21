import SwiftUI
import AppResetKit

/// Drives the detail pane: loads a full `AppReport` for the selected app and
/// performs resets, reloading afterward.
@MainActor
@Observable
final class AppDetailModel {
    private let service = AppResetService()

    var report: AppReport?
    var isLoading = false
    var isResetting = false
    var statusMessage: String?
    var statusIsError = false
    /// Files moved to the Trash this session (restorable). Cleared when switching
    /// apps or after a permanent delete / restore.
    var trashedItems: [TrashedItem] = []

    @ObservationIgnored private var statusClearTask: Task<Void, Never>?

    func load(_ app: AppInfo) async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        trashedItems = []
        // The GUI has no keychain section; skip those lookups (faster, no stalls).
        report = await service.report(for: app, includeKeychain: false)
    }

    func reload(_ app: AppInfo) async {
        isLoading = true
        defer { isLoading = false }
        report = await service.report(for: app, includeKeychain: false)
    }

    /// Re-scan with a visible confirmation, so the button clearly does something.
    func rescan(_ app: AppInfo) async {
        await reload(app)
        flashStatus("Rescanned \(app.name).")
    }

    func reset(
        _ app: AppInfo,
        categories: [ResetCategory],
        permanent: Bool,
        tccService: String = "All"
    ) async {
        guard !categories.isEmpty else { return }
        isResetting = true
        defer { isResetting = false }

        let options = ResetOptions(
            dryRun: false,
            permanent: permanent,
            killCfprefsd: true,
            tccService: tccService,
            deleteKeychain: categories.contains(.keychain)
        )
        let results = await service.reset(app, categories: categories, options: options)
        let succeeded = results.filter(\.succeeded).count
        let failed = results.filter { !$0.succeeded && !$0.skipped }.count

        // Track newly trashed files so the user can restore them.
        let newlyTrashed = results.compactMap { result -> TrashedItem? in
            guard result.succeeded,
                  let trashed = result.trashedPath,
                  let original = result.item.path else { return nil }
            return TrashedItem(originalPath: original, trashedPath: trashed)
        }
        if permanent { trashedItems = [] }   // permanent deletes can't be restored
        trashedItems.append(contentsOf: newlyTrashed)

        let message = failed > 0
            ? "\(succeeded) reset, \(failed) failed."
            : (succeeded > 0 ? "\(succeeded) item\(succeeded == 1 ? "" : "s") reset." : "Nothing to reset.")
        flashStatus(message, isError: failed > 0)

        await reload(app)
    }

    /// Restores everything this session moved to the Trash.
    func restore(_ app: AppInfo) async {
        guard !trashedItems.isEmpty else { return }
        isResetting = true
        defer { isResetting = false }
        let count = await service.restoreFromTrash(trashedItems)
        trashedItems = []
        flashStatus(count > 0 ? "Restored \(count) item\(count == 1 ? "" : "s")." : "Nothing to restore.")
        await reload(app)
    }

    /// Shows a status message that fades on its own after a few seconds.
    private func flashStatus(_ message: String, isError: Bool = false) {
        statusMessage = message
        statusIsError = isError
        statusClearTask?.cancel()
        statusClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }
}
