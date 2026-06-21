import Foundation

/// Environment probes: Full Disk Access detection and `doctor`-style diagnostics.
public struct AppEnvironment: Sendable {
    private let tcc: TCCDatabase
    private let runner: ProcessRunner

    public init(tcc: TCCDatabase = TCCDatabase(), runner: ProcessRunner = ProcessRunner()) {
        self.tcc = tcc
        self.runner = runner
    }

    /// Best-effort Full Disk Access check. Listing the SIP-/TCC-protected
    /// `com.apple.TCC` directory only succeeds when the running process has been
    /// granted Full Disk Access, which also gates reading the user TCC database.
    public func hasFullDiskAccess() -> Bool {
        let tccDir = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC"
        if (try? FileManager.default.contentsOfDirectory(atPath: tccDir)) != nil {
            return true
        }
        // Fall back to attempting an actual read of the user database.
        return tcc.userDatabaseReadable()
    }

    /// Snapshot of environment readiness. `appCount` is provided by the caller to
    /// avoid a second full enumeration.
    public func diagnostics(appCount: Int) -> Diagnostics {
        Diagnostics(
            homeDirectory: NSHomeDirectory(),
            fullDiskAccess: hasFullDiskAccess(),
            userTCCExists: tcc.userDatabaseExists(),
            userTCCReadable: tcc.userDatabaseReadable(),
            systemTCCReadable: tcc.systemDatabaseReadable(),
            tccutilAvailable: FileManager.default.isExecutableFile(atPath: "/usr/bin/tccutil"),
            appCount: appCount
        )
    }
}
