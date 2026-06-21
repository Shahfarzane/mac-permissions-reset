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

    func load(_ app: AppInfo) async {
        isLoading = true
        defer { isLoading = false }
        statusMessage = nil
        // The GUI has no keychain section; skip those lookups (faster, no stalls).
        report = await service.report(for: app, includeKeychain: false)
    }

    func reload(_ app: AppInfo) async {
        // The GUI has no keychain section; skip those lookups (faster, no stalls).
        report = await service.report(for: app, includeKeychain: false)
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
        statusIsError = failed > 0
        statusMessage = failed > 0
            ? "\(succeeded) reset, \(failed) failed."
            : (succeeded > 0 ? "\(succeeded) item\(succeeded == 1 ? "" : "s") reset." : "Nothing to reset.")

        await reload(app)
    }
}
