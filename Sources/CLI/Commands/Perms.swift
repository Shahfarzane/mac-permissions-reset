import ArgumentParser
import AppResetKit
import Foundation

struct Perms: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "perms",
        abstract: "Show current privacy (TCC) permission grants for an app."
    )

    @Argument(help: "Bundle id, app name, or path to a .app.")
    var app: String

    @Flag(name: .long, help: "Include Apple/system apps when matching by name.")
    var all = false

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        let console = global.console
        try await runCommand(console) {
            let service = AppResetService()
            let resolved = try await service.resolve(app, includeSystem: all)
            let grants = await service.grants(for: resolved)

            switch console.format {
            case .json:
                console.json(grants)
            case .plain:
                for grant in grants {
                    console.out([grant.service, grant.state.rawValue, grant.sourceDB.rawValue].joined(separator: "\t"))
                }
            case .text:
                console.out(console.heading("\(resolved.name) — privacy permissions"))
                if grants.isEmpty {
                    console.out("No TCC records for \(resolved.bundleID).")
                    if !service.hasFullDiskAccess() {
                        console.warn("Full Disk Access is not granted — per-app grants in the user database can't be read. Run `appreset doctor`.")
                    }
                    return
                }
                console.table(
                    headers: ["Service", "State", "Source", "Last Modified"],
                    rows: grants.map { grant in
                        [grant.friendlyName,
                         colorState(grant.state, console),
                         grant.sourceDB.rawValue,
                         grant.lastModified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—"]
                    }
                )
            }
        }
    }
}

/// Colorize a TCC state for terminal output.
func colorState(_ state: TCCAuthState, _ console: Console) -> String {
    switch state {
    case .allowed: return console.style(state.label, .green)
    case .denied: return console.style(state.label, .red)
    case .limited: return console.style(state.label, .yellow)
    case .unknown, .notRequested: return console.style(state.label, .dim)
    }
}
