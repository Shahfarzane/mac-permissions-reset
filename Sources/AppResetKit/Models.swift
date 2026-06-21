import Foundation

// MARK: - Apps

/// Where an application lives on disk, used to separate third-party apps from
/// Apple's bundled ones in listings.
public enum AppSource: String, Sendable, Codable, Hashable {
    case user       // /Applications, ~/Applications, etc.
    case system     // /System/Applications and other OS locations
}

/// Lightweight metadata for an installed application bundle. Cheap to build for
/// every app during enumeration; richer signing details are fetched on demand.
public struct AppInfo: Sendable, Codable, Hashable, Identifiable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let version: String?      // CFBundleShortVersionString
    public let build: String?        // CFBundleVersion
    public let path: String          // absolute path to the .app bundle
    public let executableName: String?
    public let source: AppSource

    public var isAppleSystem: Bool { source == .system }

    public init(
        bundleID: String,
        name: String,
        version: String?,
        build: String?,
        path: String,
        executableName: String?,
        source: AppSource
    ) {
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.build = build
        self.path = path
        self.executableName = executableName
        self.source = source
    }
}

/// Code-signing facts about an app, resolved lazily via `codesign`.
public struct SigningInfo: Sendable, Codable, Hashable {
    public let teamID: String?
    public let authority: String?    // leaf authority, e.g. "Developer ID Application: …"
    public let isSandboxed: Bool
    public let isAdHoc: Bool

    public init(teamID: String?, authority: String?, isSandboxed: Bool, isAdHoc: Bool) {
        self.teamID = teamID
        self.authority = authority
        self.isSandboxed = isSandboxed
        self.isAdHoc = isAdHoc
    }
}

// MARK: - Declared permissions

/// Where a declared permission was discovered.
public enum DeclaredSource: String, Sendable, Codable, Hashable {
    case usageDescription   // NS…UsageDescription key in Info.plist
    case entitlement        // com.apple.security.* entitlement
    case tccAllow           // com.apple.private.tcc.allow array (Apple apps)
}

/// A permission an app *declares* it may use — i.e. what it is built to request.
/// Distinct from `TCCGrant`, which is what the user has actually granted.
public struct DeclaredPermission: Sendable, Codable, Hashable, Identifiable {
    public var id: String { source.rawValue + "|" + rawKey }
    public let rawKey: String         // NSCameraUsageDescription / com.apple.security.device.camera / kTCCServiceCamera
    public let friendlyName: String   // "Camera"
    public let source: DeclaredSource
    public let detail: String?        // usage-description text or entitlement value
    public let tccService: String?    // mapped kTCCService… identifier, if any

    public init(
        rawKey: String,
        friendlyName: String,
        source: DeclaredSource,
        detail: String?,
        tccService: String?
    ) {
        self.rawKey = rawKey
        self.friendlyName = friendlyName
        self.source = source
        self.detail = detail
        self.tccService = tccService
    }
}

// MARK: - TCC grants

public enum TCCDatabaseScope: String, Sendable, Codable, Hashable {
    case user     // ~/Library/Application Support/com.apple.TCC/TCC.db
    case system   // /Library/Application Support/com.apple.TCC/TCC.db
}

/// Current authorization state for a service, derived from the TCC `auth_value`.
public enum TCCAuthState: String, Sendable, Codable, Hashable {
    case allowed        // auth_value 2
    case denied         // auth_value 0 (record exists)
    case limited        // auth_value 3 (e.g. Photos limited)
    case unknown        // auth_value 1 or unrecognised
    case notRequested   // no record present

    public var label: String {
        switch self {
        case .allowed: return "Allowed"
        case .denied: return "Denied"
        case .limited: return "Limited"
        case .unknown: return "Unknown"
        case .notRequested: return "Not requested"
        }
    }
}

/// A single row of TCC authorization for an app.
public struct TCCGrant: Sendable, Codable, Hashable, Identifiable {
    public var id: String { sourceDB.rawValue + "|" + service + "|" + client }
    public let service: String        // kTCCService…
    public let friendlyName: String
    public let client: String         // bundle id or executable path
    public let clientType: Int        // 0 = bundle id, 1 = absolute path
    public let state: TCCAuthState
    public let sourceDB: TCCDatabaseScope
    public let lastModified: Date?

    public init(
        service: String,
        friendlyName: String,
        client: String,
        clientType: Int,
        state: TCCAuthState,
        sourceDB: TCCDatabaseScope,
        lastModified: Date?
    ) {
        self.service = service
        self.friendlyName = friendlyName
        self.client = client
        self.clientType = clientType
        self.state = state
        self.sourceDB = sourceDB
        self.lastModified = lastModified
    }
}

// MARK: - On-disk data

/// A class of per-app data on disk. Reset categories below mirror these.
public enum DataCategory: String, Sendable, Codable, Hashable, CaseIterable {
    case preferences
    case preferencesByHost
    case container
    case groupContainer
    case caches
    case applicationSupport
    case savedState
    case httpStorages
    case webKit
    case cookies
    case logs
    case launchAgents

    public var label: String {
        switch self {
        case .preferences: return "Preferences"
        case .preferencesByHost: return "Preferences (ByHost)"
        case .container: return "Sandbox Container"
        case .groupContainer: return "Group Container"
        case .caches: return "Caches"
        case .applicationSupport: return "Application Support"
        case .savedState: return "Saved Application State"
        case .httpStorages: return "HTTP Storages"
        case .webKit: return "WebKit Storage"
        case .cookies: return "Cookies"
        case .logs: return "Logs"
        case .launchAgents: return "Launch Agents"
        }
    }
}

/// A concrete file or directory belonging to an app, with its measured size.
public struct DataLocation: Sendable, Codable, Hashable, Identifiable {
    public var id: String { path }
    public let category: DataCategory
    public let path: String
    public let exists: Bool
    public let isDirectory: Bool
    public let sizeBytes: Int64

    public init(category: DataCategory, path: String, exists: Bool, isDirectory: Bool, sizeBytes: Int64) {
        self.category = category
        self.path = path
        self.exists = exists
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
    }
}

/// A keychain item associated with an app (best-effort discovery).
public struct KeychainItem: Sendable, Codable, Hashable, Identifiable {
    public var id: String { kind.rawValue + "|" + service + "|" + account }
    public enum Kind: String, Sendable, Codable, Hashable {
        case generic    // generic password
        case internet   // internet password
    }
    public let kind: Kind
    public let service: String
    public let account: String

    public init(kind: Kind, service: String, account: String) {
        self.kind = kind
        self.service = service
        self.account = account
    }
}

// MARK: - Reset

/// A category of state a user can reset for an app.
public enum ResetCategory: String, Sendable, Codable, Hashable, CaseIterable {
    case tcc              // tccutil reset (privacy permissions)
    case defaults         // UserDefaults / preferences (delete + cfprefsd flush)
    case caches
    case containers
    case groupContainers
    case appSupport
    case savedState
    case httpStorages
    case webKit
    case cookies
    case logs
    case launchAgents
    case keychain

    public var label: String {
        switch self {
        case .tcc: return "Privacy Permissions (TCC)"
        case .defaults: return "Preferences / UserDefaults"
        case .caches: return "Caches"
        case .containers: return "Sandbox Containers"
        case .groupContainers: return "Group Containers"
        case .appSupport: return "Application Support"
        case .savedState: return "Saved Application State"
        case .httpStorages: return "HTTP Storages"
        case .webKit: return "WebKit Storage"
        case .cookies: return "Cookies"
        case .logs: return "Logs"
        case .launchAgents: return "Launch Agents"
        case .keychain: return "Keychain Items"
        }
    }

    /// Categories included by `all` / the default reset. Keychain and launch
    /// agents are excluded from the default sweep because they are higher-risk
    /// and less about "clean first-run" testing; opt in explicitly.
    public static var defaultSweep: [ResetCategory] {
        [.tcc, .defaults, .caches, .containers, .groupContainers,
         .appSupport, .savedState, .httpStorages, .webKit, .cookies, .logs]
    }
}

public enum ResetActionKind: String, Sendable, Codable, Hashable {
    case tccReset
    case defaultsDelete
    case trash
    case delete
    case killProcess
    case keychainDelete
}

/// One planned reset operation. A plan is a list of these; with `dryRun` the
/// engine returns the plan without executing.
public struct ResetItem: Sendable, Codable, Hashable, Identifiable {
    public var id: String { category.rawValue + "|" + action.rawValue + "|" + (path ?? command ?? detail ?? "") }
    public let category: ResetCategory
    public let action: ResetActionKind
    public let path: String?        // for file operations
    public let command: String?     // human-readable command, e.g. "tccutil reset All com.x"
    public let sizeBytes: Int64?
    public let detail: String?

    public init(
        category: ResetCategory,
        action: ResetActionKind,
        path: String? = nil,
        command: String? = nil,
        sizeBytes: Int64? = nil,
        detail: String? = nil
    ) {
        self.category = category
        self.action = action
        self.path = path
        self.command = command
        self.sizeBytes = sizeBytes
        self.detail = detail
    }
}

public struct ResetResult: Sendable, Codable, Hashable, Identifiable {
    public var id: String { item.id }
    public let item: ResetItem
    public let succeeded: Bool
    public let skipped: Bool
    public let message: String?
    /// Where a trashed file landed in the user's Trash, so it can be restored.
    /// `nil` for permanent deletes and non-file actions.
    public let trashedPath: String?

    public init(item: ResetItem, succeeded: Bool, skipped: Bool, message: String?, trashedPath: String? = nil) {
        self.item = item
        self.succeeded = succeeded
        self.skipped = skipped
        self.message = message
        self.trashedPath = trashedPath
    }
}

/// A file moved to the Trash by a reset, paired with its original location so the
/// GUI can offer a one-click restore.
public struct TrashedItem: Sendable, Hashable, Identifiable {
    public var id: String { trashedPath }
    public let originalPath: String
    public let trashedPath: String

    public init(originalPath: String, trashedPath: String) {
        self.originalPath = originalPath
        self.trashedPath = trashedPath
    }
}

/// Options controlling a reset run.
public struct ResetOptions: Sendable, Hashable {
    public var dryRun: Bool
    public var permanent: Bool        // true = delete, false = move to Trash
    public var killCfprefsd: Bool     // flush the preferences cache after deleting defaults
    public var tccService: String     // "All" or a specific kTCCService… identifier
    public var deleteKeychain: Bool   // actually delete discovered keychain items

    public init(
        dryRun: Bool = false,
        permanent: Bool = false,
        killCfprefsd: Bool = true,
        tccService: String = "All",
        deleteKeychain: Bool = false
    ) {
        self.dryRun = dryRun
        self.permanent = permanent
        self.killCfprefsd = killCfprefsd
        self.tccService = tccService
        self.deleteKeychain = deleteKeychain
    }
}

// MARK: - Diagnostics

/// Environment readiness, surfaced by `appreset doctor` and the GUI banner.
public struct Diagnostics: Sendable, Codable, Hashable {
    public let homeDirectory: String
    public let fullDiskAccess: Bool
    public let userTCCExists: Bool
    public let userTCCReadable: Bool
    public let systemTCCReadable: Bool
    public let tccutilAvailable: Bool
    public let appCount: Int

    public init(
        homeDirectory: String,
        fullDiskAccess: Bool,
        userTCCExists: Bool,
        userTCCReadable: Bool,
        systemTCCReadable: Bool,
        tccutilAvailable: Bool,
        appCount: Int
    ) {
        self.homeDirectory = homeDirectory
        self.fullDiskAccess = fullDiskAccess
        self.userTCCExists = userTCCExists
        self.userTCCReadable = userTCCReadable
        self.systemTCCReadable = systemTCCReadable
        self.tccutilAvailable = tccutilAvailable
        self.appCount = appCount
    }
}

// MARK: - Errors

public enum AppResetError: Error, Sendable, CustomStringConvertible, Equatable {
    case appNotFound(query: String)
    case ambiguousApp(query: String, matches: [String])
    case processLaunchFailed(tool: String, underlying: String)
    case processFailed(command: String, exitCode: Int32, stderr: String)
    case sqlite(String)
    case io(String)
    case fullDiskAccessRequired(String)

    public var description: String {
        switch self {
        case .appNotFound(let query):
            return "No app found matching \"\(query)\"."
        case .ambiguousApp(let query, let matches):
            return "\"\(query)\" matches multiple apps: \(matches.joined(separator: ", ")). Use a bundle id."
        case .processLaunchFailed(let tool, let underlying):
            return "Failed to launch \(tool): \(underlying)"
        case .processFailed(let command, let exitCode, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Command failed (exit \(exitCode)): \(command)" + (trimmed.isEmpty ? "" : "\n\(trimmed)")
        case .sqlite(let message):
            return "TCC database error: \(message)"
        case .io(let message):
            return message
        case .fullDiskAccessRequired(let context):
            return "Full Disk Access is required to \(context)."
        }
    }
}
