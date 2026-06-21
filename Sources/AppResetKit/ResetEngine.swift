import Foundation

/// Plans and executes the set of operations that reset an app's state — TCC
/// privacy grants, preferences, on-disk data and keychain items.
///
/// `plan(...)` is pure: given the inputs it computed elsewhere (data locations,
/// TCC grants, keychain items) it returns an ordered list of `ResetItem`s and
/// performs no side effects. `execute(...)` carries those items out, honouring
/// `ResetOptions` (dry run, permanent vs. trash, cfprefsd flush, …) and never
/// crashing on a malformed item.
public struct ResetEngine: Sendable {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    // MARK: - Planning

    /// Maps a file-backed `ResetCategory` to the `DataCategory` it operates on.
    ///
    /// Preference categories (`.preferences` / `.preferencesByHost`) are
    /// deliberately absent: those are handled by the `defaults delete` step, not
    /// by trashing/deleting the plist files directly.
    private static func dataCategory(for category: ResetCategory) -> DataCategory? {
        switch category {
        case .caches:          return .caches
        case .containers:      return .container
        case .groupContainers: return .groupContainer
        case .appSupport:      return .applicationSupport
        case .savedState:      return .savedState
        case .httpStorages:    return .httpStorages
        case .webKit:          return .webKit
        case .cookies:         return .cookies
        case .logs:            return .logs
        case .launchAgents:    return .launchAgents
        case .tcc, .defaults, .keychain:
            return nil
        }
    }

    /// Stable ordering for emitted items: TCC first, then defaults, then each
    /// file-backed category in declaration order, then keychain last.
    private static let categoryOrder: [ResetCategory] = [
        .tcc, .defaults,
        .caches, .containers, .groupContainers, .appSupport, .savedState,
        .httpStorages, .webKit, .cookies, .logs, .launchAgents,
        .keychain,
    ]

    /// Build the ordered list of reset operations for `app`.
    ///
    /// Pure — produces no side effects. Only categories present in `categories`
    /// are included. File items are created from `dataLocations` whose
    /// `category` maps onto a requested file-backed `ResetCategory`.
    public func plan(
        app: AppInfo,
        categories: [ResetCategory],
        dataLocations: [DataLocation],
        grants: [TCCGrant],
        keychainItems: [KeychainItem],
        options: ResetOptions
    ) -> [ResetItem] {
        let requested = Set(categories)
        var items: [ResetItem] = []

        for category in Self.categoryOrder where requested.contains(category) {
            switch category {
            case .tcc:
                let names = grants.map(\.friendlyName)
                let detail = names.isEmpty ? nil : names.joined(separator: ", ")
                items.append(
                    ResetItem(
                        category: .tcc,
                        action: .tccReset,
                        command: "tccutil reset \(options.tccService) \(app.bundleID)",
                        detail: detail
                    )
                )

            case .defaults:
                items.append(
                    ResetItem(
                        category: .defaults,
                        action: .defaultsDelete,
                        command: "defaults delete \(app.bundleID)"
                    )
                )

            case .keychain:
                for item in keychainItems {
                    let kind = item.kind == .generic ? "generic" : "internet"
                    items.append(
                        ResetItem(
                            category: .keychain,
                            action: .keychainDelete,
                            command: "security delete-\(kind)-password -s \(item.service)",
                            detail: "service=\(item.service) account=\(item.account)"
                        )
                    )
                }

            case .caches, .containers, .groupContainers, .appSupport, .savedState,
                 .httpStorages, .webKit, .cookies, .logs, .launchAgents:
                guard let dataCategory = Self.dataCategory(for: category) else { continue }
                for loc in dataLocations where loc.category == dataCategory {
                    items.append(
                        ResetItem(
                            category: category,
                            action: options.permanent ? .delete : .trash,
                            path: loc.path,
                            sizeBytes: loc.sizeBytes
                        )
                    )
                }
            }
        }

        return items
    }

    // MARK: - Execution

    /// Carry out `items` in order, returning one `ResetResult` per item.
    ///
    /// When `options.dryRun` is set, nothing is touched and every item is marked
    /// `skipped`. Otherwise each item is dispatched on its action. File
    /// operations run off the caller's executor; process-backed actions use the
    /// injected `ProcessRunner`. Results are returned in input order.
    public func execute(_ items: [ResetItem], options: ResetOptions) async -> [ResetResult] {
        var results: [ResetResult] = []
        results.reserveCapacity(items.count)

        for item in items {
            if options.dryRun {
                results.append(
                    ResetResult(item: item, succeeded: false, skipped: true, message: "dry run — no changes")
                )
                continue
            }

            let result: ResetResult
            switch item.action {
            case .trash:
                result = await Self.trash(item)
            case .delete:
                result = await Self.delete(item)
            case .defaultsDelete:
                result = await defaultsDelete(item, options: options)
            case .tccReset:
                result = await tccReset(item)
            case .keychainDelete:
                result = await keychainDelete(item)
            case .killProcess:
                result = await killProcess(item)
            }
            results.append(result)
        }

        return results
    }

    // MARK: - File actions

    private static func trash(_ item: ResetItem) async -> ResetResult {
        guard let path = item.path else {
            return ResetResult(item: item, succeeded: false, skipped: false, message: "missing path")
        }
        return await Offload.run {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                return ResetResult(item: item, succeeded: true, skipped: false, message: nil)
            } catch {
                return ResetResult(item: item, succeeded: false, skipped: false, message: error.localizedDescription)
            }
        }
    }

    private static func delete(_ item: ResetItem) async -> ResetResult {
        guard let path = item.path else {
            return ResetResult(item: item, succeeded: false, skipped: false, message: "missing path")
        }
        return await Offload.run {
            do {
                try FileManager.default.removeItem(atPath: path)
                return ResetResult(item: item, succeeded: true, skipped: false, message: nil)
            } catch {
                return ResetResult(item: item, succeeded: false, skipped: false, message: error.localizedDescription)
            }
        }
    }

    // MARK: - defaults

    private func defaultsDelete(_ item: ResetItem, options: ResetOptions) async -> ResetResult {
        guard let command = item.command,
              let bundleID = command.split(whereSeparator: \.isWhitespace).last.map(String.init),
              !bundleID.isEmpty else {
            return ResetResult(item: item, succeeded: false, skipped: false, message: "missing command")
        }

        do {
            let primary = try await runner.run("defaults", ["delete", bundleID])

            // Best-effort: clear the by-host domain too, ignoring its outcome.
            _ = try? await runner.run("defaults", ["-currentHost", "delete", bundleID])

            if options.killCfprefsd {
                _ = try? await runner.run("killall", ["cfprefsd"])
            }

            if primary.ok {
                return ResetResult(item: item, succeeded: true, skipped: false, message: nil)
            }

            // A missing domain is a success for our purposes — there were simply
            // no preferences to remove. macOS phrases this as "Domain '…' not
            // found." / "does not exist".
            let output = (primary.stderr + primary.stdout).lowercased()
            if output.contains("not found") || output.contains("does not exist") {
                return ResetResult(item: item, succeeded: true, skipped: false, message: "no preferences found")
            }

            let stderr = primary.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return ResetResult(
                item: item,
                succeeded: false,
                skipped: false,
                message: stderr.isEmpty ? "defaults delete failed (exit \(primary.exitCode))" : stderr
            )
        } catch {
            return ResetResult(item: item, succeeded: false, skipped: false, message: "\(error)")
        }
    }

    // MARK: - Command-backed actions

    private func tccReset(_ item: ResetItem) async -> ResetResult {
        await runCommand(item) { result in
            if result.ok {
                return ResetResult(item: item, succeeded: true, skipped: false, message: nil)
            }
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return ResetResult(
                item: item,
                succeeded: false,
                skipped: false,
                message: stderr.isEmpty ? "tccutil failed (exit \(result.exitCode))" : stderr
            )
        }
    }

    private func keychainDelete(_ item: ResetItem) async -> ResetResult {
        await runCommand(item) { result in
            if result.ok {
                return ResetResult(item: item, succeeded: true, skipped: false, message: nil)
            }
            // `security` returns 44 (errSecItemNotFound) when nothing matched —
            // treat that as a benign success.
            if result.exitCode == 44 {
                return ResetResult(item: item, succeeded: true, skipped: false, message: "no keychain item")
            }
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return ResetResult(
                item: item,
                succeeded: false,
                skipped: false,
                message: stderr.isEmpty ? "security failed (exit \(result.exitCode))" : stderr
            )
        }
    }

    private func killProcess(_ item: ResetItem) async -> ResetResult {
        await runCommand(item) { result in
            if result.ok {
                return ResetResult(item: item, succeeded: true, skipped: false, message: nil)
            }
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return ResetResult(
                item: item,
                succeeded: false,
                skipped: false,
                message: stderr.isEmpty ? "command failed (exit \(result.exitCode))" : stderr
            )
        }
    }

    /// Split `item.command` into argv, run the first token as the executable and
    /// hand the resulting `ProcessResult` to `interpret`. Guards a nil/empty
    /// command and a launch failure rather than crashing.
    private func runCommand(
        _ item: ResetItem,
        interpret: (ProcessResult) -> ResetResult
    ) async -> ResetResult {
        guard let command = item.command else {
            return ResetResult(item: item, succeeded: false, skipped: false, message: "missing command")
        }
        let argv = command.split(separator: " ").map(String.init)
        guard let executable = argv.first else {
            return ResetResult(item: item, succeeded: false, skipped: false, message: "empty command")
        }

        do {
            let result = try await runner.run(executable, Array(argv.dropFirst()))
            return interpret(result)
        } catch {
            return ResetResult(item: item, succeeded: false, skipped: false, message: "\(error)")
        }
    }
}
