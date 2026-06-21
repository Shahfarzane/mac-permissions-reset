import ArgumentParser
import AppResetKit
import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct Reset: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Reset privacy permissions and/or delete an app's data.",
        discussion: """
        Categories (comma-separated, for --what / --keep):
          tcc, defaults, caches, containers, groupcontainers, appsupport,
          savedstate, httpstorages, webkit, cookies, logs, launchagents, keychain, all

        "all" expands to everything except keychain and launchagents (add those
        explicitly, e.g. --what all,keychain). Data is moved to the Trash unless
        --permanent is given. A terminal prompts for confirmation; non-interactive
        use requires --yes.
        """
    )

    @Argument(help: "Bundle id, app name, or path to a .app.")
    var app: String

    @Option(name: .long, help: "Categories to reset (default: all).")
    var what: String = "all"

    @Option(name: .long, help: "Categories to keep (exclude from the reset).")
    var keep: String?

    @Flag(name: [.customShort("n"), .long], help: "Preview the plan without making changes.")
    var dryRun = false

    @Flag(name: [.customShort("y"), .customLong("yes"), .customLong("force")],
          help: "Skip confirmation (required in non-interactive use).")
    var yes = false

    @Flag(name: .long, help: "Permanently delete instead of moving to the Trash.")
    var permanent = false

    @Flag(name: .long, help: "Don't restart cfprefsd after deleting preferences.")
    var noKill = false

    @Option(name: .long, help: "Limit a TCC reset to a single service (default: All).")
    var tccService: String?

    @Flag(name: .long, help: "Include Apple/system apps when matching by name.")
    var all = false

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        let console = global.console
        let categories = try parseResetCategories(what: what, keep: keep)

        try await runCommand(console) {
            let service = AppResetService()
            let resolved = try await service.resolve(app, includeSystem: all)

            let options = ResetOptions(
                dryRun: dryRun,
                permanent: permanent,
                killCfprefsd: !noKill,
                tccService: tccService ?? "All",
                deleteKeychain: categories.contains(.keychain)
            )

            let plan = await service.plan(for: resolved, categories: categories, options: options)
            guard !plan.isEmpty else {
                console.info("Nothing to reset for \(resolved.bundleID).")
                return
            }

            renderPlan(plan, app: resolved, console: console, permanent: permanent)

            if dryRun {
                console.info(console.style("dry run — nothing was changed", .dim))
                return
            }

            if !yes {
                guard isatty(STDIN_FILENO) != 0 else {
                    console.error("refusing to run a destructive reset without --yes in a non-interactive session")
                    throw ExitCode(64)
                }
                FileHandle.standardError.write(Data("Proceed? [y/N] ".utf8))
                let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                guard answer == "y" || answer == "yes" else {
                    console.info("Aborted.")
                    return
                }
            }

            let results = await service.execute(plan, options: options)
            try reportResults(results, console: console)
        }
    }

    private func renderPlan(_ plan: [ResetItem], app: AppInfo, console: Console, permanent: Bool) {
        console.out(console.heading("Reset plan for \(app.name) — \(plan.count) operation\(plan.count == 1 ? "" : "s")"))
        var freed: Int64 = 0
        for item in plan {
            let line: String
            switch item.action {
            case .tccReset:
                line = "Reset privacy: \(item.command ?? "tccutil reset")"
            case .defaultsDelete:
                line = "Delete preferences: \(item.command ?? "defaults delete")"
            case .keychainDelete:
                line = "Delete keychain item: \(item.detail ?? item.command ?? "")"
            case .trash, .delete:
                let verb = item.action == .trash ? "Trash" : "Delete"
                let size = item.sizeBytes.map { " (\(Console.bytes($0)))" } ?? ""
                freed += item.sizeBytes ?? 0
                line = "\(verb) \(item.category.label): \(abbreviateHome(item.path ?? ""))\(size)"
            case .killProcess:
                line = item.command ?? "kill process"
            }
            console.out("  \(console.style("•", .blue)) \(line)")
        }
        if freed > 0 {
            console.info("Frees ~\(Console.bytes(freed))\(permanent ? "" : " (recoverable from Trash)")")
        }
    }

    private func reportResults(_ results: [ResetResult], console: Console) throws {
        if console.format == .json {
            console.json(results)
        } else {
            for result in results {
                let mark: String
                if result.skipped {
                    mark = console.style("○", .dim)
                } else if result.succeeded {
                    mark = console.style("✓", .green)
                } else {
                    mark = console.style("✗", .red)
                }
                let label = result.item.path.map(abbreviateHome) ?? result.item.command ?? result.item.category.label
                let note = result.message.map { " \(console.style("(\($0))", .dim))" } ?? ""
                console.out("\(mark) \(label)\(note)")
            }
        }

        let failed = results.filter { !$0.succeeded && !$0.skipped }.count
        let succeeded = results.filter { $0.succeeded }.count
        console.info("Done: \(succeeded) succeeded, \(failed) failed.")
        if failed > 0 {
            throw ExitCode(3)
        }
    }
}

private let categoryTokens: [String: ResetCategory] = [
    "tcc": .tcc, "privacy": .tcc,
    "defaults": .defaults, "preferences": .defaults, "prefs": .defaults,
    "caches": .caches, "cache": .caches,
    "containers": .containers, "container": .containers,
    "groupcontainers": .groupContainers, "groupcontainer": .groupContainers, "group": .groupContainers,
    "appsupport": .appSupport, "applicationsupport": .appSupport,
    "savedstate": .savedState, "saved": .savedState,
    "httpstorages": .httpStorages, "http": .httpStorages,
    "webkit": .webKit, "web": .webKit,
    "cookies": .cookies,
    "logs": .logs, "log": .logs,
    "launchagents": .launchAgents, "launch": .launchAgents,
    "keychain": .keychain,
]

/// Parse the --what / --keep token lists into a concrete category set.
func parseResetCategories(what: String, keep: String?) throws -> [ResetCategory] {
    func tokens(_ string: String) -> [String] {
        string.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    var selected = Set<ResetCategory>()
    for token in tokens(what) {
        if token == "all" {
            selected.formUnion(ResetCategory.defaultSweep)
        } else if let category = categoryTokens[token] {
            selected.insert(category)
        } else {
            throw ValidationError("Unknown category \"\(token)\". See `appreset reset --help` for the list.")
        }
    }

    if let keep {
        for token in tokens(keep) {
            if token == "all" {
                selected.removeAll()
            } else if let category = categoryTokens[token] {
                selected.remove(category)
            } else {
                throw ValidationError("Unknown category \"\(token)\" in --keep.")
            }
        }
    }

    // Return in the canonical category order.
    return ResetCategory.allCases.filter { selected.contains($0) }
}
