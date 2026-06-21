import ArgumentParser
import AppResetKit

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List installed applications.",
        discussion: "Shows third-party apps by default; pass --all to include Apple/system apps."
    )

    @Flag(name: .long, help: "Include Apple and system apps.")
    var all = false

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        let console = global.console
        try await runCommand(console) {
            let service = AppResetService()
            let apps = await service.listApps(includeSystem: all)

            switch console.format {
            case .json:
                console.json(apps)
            case .plain:
                for app in apps {
                    console.out([app.bundleID, app.name, app.version ?? "", app.path].joined(separator: "\t"))
                }
            case .text:
                if apps.isEmpty {
                    console.info("No apps found.")
                    return
                }
                console.table(
                    headers: ["Name", "Version", "Bundle ID"],
                    rows: apps.map { [$0.name, $0.version ?? "—", $0.bundleID] }
                )
                console.info("\(apps.count) app\(apps.count == 1 ? "" : "s")")
            }
        }
    }
}
