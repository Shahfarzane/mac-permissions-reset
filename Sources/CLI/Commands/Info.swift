import ArgumentParser
import AppResetKit
import Foundation

struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show an app's declared permissions, current grants, and data footprint."
    )

    @Argument(help: "Bundle id, app name, or path to a .app.")
    var app: String

    @Flag(name: .long, help: "Include Apple/system apps when matching by name.")
    var all = false

    @Flag(name: .long, help: "Skip keychain lookups (faster).")
    var noKeychain = false

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        let console = global.console
        try await runCommand(console) {
            let service = AppResetService()
            let resolved = try await service.resolve(app, includeSystem: all)
            let report = await service.report(for: resolved, includeKeychain: !noKeychain)

            if console.format == .json {
                console.json(report)
                return
            }

            renderIdentity(report, console)
            renderDeclared(report, console)
            renderGrants(report, console, service: service)
            renderData(report, console)
            if !noKeychain { renderKeychain(report, console) }
        }
    }

    private func renderIdentity(_ report: AppReport, _ console: Console) {
        console.out(console.heading(report.app.name))
        var rows: [[String]] = [
            ["Bundle ID", report.app.bundleID],
            ["Version", [report.app.version, report.app.build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")],
            ["Path", abbreviateHome(report.app.path)],
            ["Kind", isAppleApp(report.app) ? "Apple" : "Third-party"],
        ]
        if let team = report.signing.teamID { rows.append(["Team ID", team]) }
        if let authority = report.signing.authority { rows.append(["Signed by", authority]) }
        rows.append(["Sandboxed", report.signing.isSandboxed ? "yes" : "no"])
        console.table(headers: ["", ""], rows: rows)
        console.out()
    }

    private func renderDeclared(_ report: AppReport, _ console: Console) {
        console.out(console.heading("Declared permissions (\(report.declared.count))"))
        if report.declared.isEmpty {
            console.out("  none declared")
        } else {
            console.table(
                headers: ["Permission", "Source", "Detail"],
                rows: report.declared.map { permission in
                    [permission.friendlyName,
                     sourceLabel(permission.source),
                     truncate(permission.detail ?? "", 60)]
                }
            )
        }
        console.out()
    }

    private func renderGrants(_ report: AppReport, _ console: Console, service: AppResetService) {
        console.out(console.heading("Privacy / TCC grants (\(report.grants.count))"))
        if report.grants.isEmpty {
            console.out("  no records")
            if !service.hasFullDiskAccess() {
                console.warn("Full Disk Access not granted — user-database grants are hidden. Run `appreset doctor`.")
            }
        } else {
            console.table(
                headers: ["Service", "State", "Source"],
                rows: report.grants.map { [$0.friendlyName, colorState($0.state, console), $0.sourceDB.rawValue] }
            )
        }
        console.out()
    }

    private func renderData(_ report: AppReport, _ console: Console) {
        console.out(console.heading("Data & storage (\(Console.bytes(report.totalDataSize)))"))
        if report.dataLocations.isEmpty {
            console.out("  no on-disk data")
        } else {
            console.table(
                headers: ["Category", "Size", "Path"],
                rows: report.dataLocations.map { [$0.category.label, Console.bytes($0.sizeBytes), abbreviateHome($0.path)] }
            )
        }
        console.out()
    }

    private func renderKeychain(_ report: AppReport, _ console: Console) {
        guard !report.keychainItems.isEmpty else { return }
        console.out(console.heading("Keychain items (\(report.keychainItems.count))"))
        console.table(
            headers: ["Kind", "Service", "Account"],
            rows: report.keychainItems.map { [$0.kind.rawValue, $0.service, $0.account] }
        )
        console.out()
    }
}

/// Treat OS-bundled apps as "Apple" whether they live in /System or /Applications.
func isAppleApp(_ app: AppInfo) -> Bool {
    app.isAppleSystem || app.bundleID.hasPrefix("com.apple.")
}

func sourceLabel(_ source: DeclaredSource) -> String {
    switch source {
    case .usageDescription: return "Usage"
    case .entitlement: return "Entitlement"
    case .tccAllow: return "TCC allow"
    }
}

func truncate(_ string: String, _ max: Int) -> String {
    let collapsed = string.replacingOccurrences(of: "\n", with: " ")
    if collapsed.count <= max { return collapsed }
    return String(collapsed.prefix(max - 1)) + "…"
}
