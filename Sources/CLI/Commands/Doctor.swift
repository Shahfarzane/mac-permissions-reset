import ArgumentParser
import AppResetKit

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check environment readiness (Full Disk Access, TCC databases)."
    )

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        let console = global.console
        try await runCommand(console) {
            let service = AppResetService()
            let diag = await service.diagnostics()

            switch console.format {
            case .json:
                console.json(diag)
            case .plain:
                console.out("full_disk_access\t\(diag.fullDiskAccess)")
                console.out("user_tcc_exists\t\(diag.userTCCExists)")
                console.out("user_tcc_readable\t\(diag.userTCCReadable)")
                console.out("system_tcc_readable\t\(diag.systemTCCReadable)")
                console.out("tccutil_available\t\(diag.tccutilAvailable)")
                console.out("app_count\t\(diag.appCount)")
                console.out("home\t\(diag.homeDirectory)")
            case .text:
                func line(_ ok: Bool, _ label: String, note: String? = nil) {
                    let mark = ok ? console.style("✓", .green) : console.style("✗", .red)
                    let suffix = note.map { " \(console.style("(\($0))", .dim))" } ?? ""
                    console.out("\(mark) \(label)\(suffix)")
                }
                console.out(console.heading("AppReset environment"))
                line(diag.fullDiskAccess, "Full Disk Access",
                     note: diag.fullDiskAccess ? nil : "grant in System Settings ▸ Privacy & Security ▸ Full Disk Access")
                line(diag.systemTCCReadable, "System TCC database readable")
                line(diag.userTCCReadable, "User TCC database readable",
                     note: diag.userTCCReadable ? nil : (diag.userTCCExists ? "needs Full Disk Access" : "not present"))
                line(diag.tccutilAvailable, "tccutil available")
                console.out("\(console.style("•", .blue)) \(diag.appCount) apps discovered")
                console.out("\(console.style("•", .blue)) Home: \(diag.homeDirectory)")
                if !diag.fullDiskAccess {
                    console.info("")
                    console.info("Without Full Disk Access, per-app privacy grants (Camera, Microphone, Contacts, …) can't be read. Resets and data scanning still work.")
                }
            }
        }
    }
}
