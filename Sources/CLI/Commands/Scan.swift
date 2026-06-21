import ArgumentParser
import AppResetKit
import Foundation

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Show on-disk data locations for an app, with sizes."
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
            let locations = await service.dataLocations(for: resolved)

            switch console.format {
            case .json:
                console.json(locations)
            case .plain:
                for loc in locations {
                    console.out([loc.category.rawValue, "\(loc.sizeBytes)", loc.path].joined(separator: "\t"))
                }
            case .text:
                console.out(console.heading("\(resolved.name) — data footprint"))
                if locations.isEmpty {
                    console.out("No on-disk data found for \(resolved.bundleID).")
                    return
                }
                console.table(
                    headers: ["Category", "Size", "Path"],
                    rows: locations.map { [$0.category.label, Console.bytes($0.sizeBytes), abbreviateHome($0.path)] }
                )
                let total = locations.reduce(Int64(0)) { $0 + $1.sizeBytes }
                console.info("Total: \(Console.bytes(total)) across \(locations.count) location\(locations.count == 1 ? "" : "s")")
            }
        }
    }
}

/// Replace the home directory prefix with `~` for compact display.
func abbreviateHome(_ path: String) -> String {
    let home = NSHomeDirectory()
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}
