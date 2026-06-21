import Foundation
import SQLite3

/// Reads the macOS Transparency, Consent, and Control (TCC) SQLite databases to
/// discover the privacy permissions an application has been granted.
///
/// There are two TCC databases on macOS:
/// - a per-user database under `~/Library/Application Support/com.apple.TCC/TCC.db`
///   (covers most user-facing services such as camera, microphone, contacts), and
/// - a system database under `/Library/Application Support/com.apple.TCC/TCC.db`
///   (covers system-policy services such as full disk access and screen capture).
///
/// Both databases are protected by SACL/SIP. Reading the user database requires the
/// calling process to have **Full Disk Access**; the system database additionally
/// requires elevated privileges. When a database cannot be opened we simply skip it
/// rather than surfacing an error, so callers always get whatever is reachable.
public struct TCCDatabase: Sendable {
    public init() {}

    /// Absolute path to the per-user TCC database.
    public static let userDBPath = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"

    /// Absolute path to the system-wide TCC database.
    public static let systemDBPath = "/Library/Application Support/com.apple.TCC/TCC.db"

    /// SQLite's special destructor constant indicating the bound value should be copied.
    /// SQLite does not expose this through its C headers in a Swift-importable form, so we
    /// reconstruct it the same way the C macro does: `((sqlite3_destructor_type)-1)`.
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: - Public queries

    /// Returns every TCC grant recorded for the given bundle identifier across both
    /// databases (system always, user when readable). The blocking SQLite work runs off
    /// the caller's executor. Databases that cannot be opened contribute no rows.
    public func grants(forBundleID bundleID: String) async -> [TCCGrant] {
        let userPath = Self.userDBPath
        let systemPath = Self.systemDBPath
        return await Offload.run {
            var result: [TCCGrant] = []
            // System database is always attempted.
            result.append(contentsOf: Self.readGrants(dbPath: systemPath, bundleID: bundleID, scope: .system))
            // User database is attempted too; it is silently skipped if unreadable / missing.
            result.append(contentsOf: Self.readGrants(dbPath: userPath, bundleID: bundleID, scope: .user))
            return result
        }
    }

    /// Whether the per-user TCC database file is present on disk.
    public func userDatabaseExists() -> Bool {
        FileManager.default.fileExists(atPath: Self.userDBPath)
    }

    /// Whether the per-user TCC database can actually be opened and queried
    /// (i.e. the process effectively has Full Disk Access).
    public func userDatabaseReadable() -> Bool {
        Self.databaseReadable(dbPath: Self.userDBPath)
    }

    /// Whether the system TCC database can actually be opened and queried.
    public func systemDatabaseReadable() -> Bool {
        Self.databaseReadable(dbPath: Self.systemDBPath)
    }

    // MARK: - Blocking SQLite helpers

    /// Opens `dbPath` read-only and reads all `access` rows whose `client` matches
    /// `bundleID`. Returns an empty array if the database cannot be opened or prepared
    /// (the common case being a missing Full Disk Access grant). Never throws.
    private static func readGrants(dbPath: String, bundleID: String, scope: TCCDatabaseScope) -> [TCCGrant] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            // Could not open (missing file, no Full Disk Access, SIP) — skip it.
            sqlite3_close(handle)
            return []
        }
        defer { sqlite3_close(handle) }

        var stmt: OpaquePointer?
        let sql = "SELECT service, client, client_type, auth_value, last_modified FROM access WHERE client = ?1"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (bundleID as NSString).utf8String, -1, SQLITE_TRANSIENT)

        var grants: [TCCGrant] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            // Guard against null text column pointers before constructing Strings.
            guard let serviceText = sqlite3_column_text(stmt, 0) else { continue }
            let service = String(cString: serviceText)

            let client: String
            if let clientText = sqlite3_column_text(stmt, 1) {
                client = String(cString: clientText)
            } else {
                client = bundleID
            }

            let clientType = Int(sqlite3_column_int(stmt, 2))
            let authValue = sqlite3_column_int(stmt, 3)
            let lastModifiedRaw = sqlite3_column_int64(stmt, 4)

            let state: TCCAuthState
            switch authValue {
            case 0: state = .denied
            case 1: state = .unknown
            case 2: state = .allowed
            case 3: state = .limited
            default: state = .unknown
            }

            let lastModified: Date? = lastModifiedRaw > 0
                ? Date(timeIntervalSince1970: Double(lastModifiedRaw))
                : nil

            grants.append(
                TCCGrant(
                    service: service,
                    friendlyName: TCCServiceCatalog.friendlyName(for: service),
                    client: client,
                    clientType: clientType,
                    state: state,
                    sourceDB: scope,
                    lastModified: lastModified
                )
            )
        }
        return grants
    }

    /// Attempts to open `dbPath` read-only and step a trivial `SELECT count(*) FROM access`.
    /// Returns `true` only if every step of that probe succeeds.
    private static func databaseReadable(dbPath: String) -> Bool {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return false
        }
        defer { sqlite3_close(handle) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT count(*) FROM access", -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            return false
        }
        defer { sqlite3_finalize(stmt) }

        return sqlite3_step(stmt) == SQLITE_ROW
    }
}
