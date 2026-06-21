import Foundation

/// Scans the macOS file system for per-application data locations (preferences,
/// containers, caches, application support, logs, and so on) belonging to a
/// specific app, measuring the on-disk size of each location that exists.
///
/// All blocking file-system work is performed off the caller's executor via
/// ``Offload/run(_:)`` so that calling this scanner does not stall a structured
/// concurrency context. The scanner never throws: any location that cannot be
/// resolved or measured is simply omitted.
public struct DataLocationScanner: Sendable {

    public init() {}

    /// Resolve every per-app data location that currently exists on disk,
    /// measure its size, and return the results de-duplicated by path and sorted
    /// by category (in `DataCategory.allCases` order) then by descending size.
    ///
    /// - Parameters:
    ///   - bundleID: The application's bundle identifier (e.g. `com.acme.App`).
    ///   - appName: The application's display name, used for the name-based
    ///     Application Support and Logs directories. Pass `nil` to skip those.
    ///   - teamID: The signing team identifier, used to match group containers
    ///     of the form `<TeamID>.<group>`. Pass `nil`/empty to skip team-prefix
    ///     matching (bundle-ID-substring matching still applies).
    /// - Returns: The existing data locations. Never throws.
    public func scan(bundleID: String, appName: String?, teamID: String?) async -> [DataLocation] {
        await Offload.run {
            Self.scanSync(bundleID: bundleID, appName: appName, teamID: teamID)
        }
    }

    // MARK: - Synchronous implementation (runs off the caller executor)

    /// Performs the blocking file-system scan. Marked `nonisolated`-friendly by
    /// being a pure static function operating only on its parameters.
    private static func scanSync(bundleID: String, appName: String?, teamID: String?) -> [DataLocation] {
        let fileManager = FileManager.default
        let home = NSHomeDirectory()

        /// A candidate path paired with the category it would be reported under.
        var candidates: [(category: DataCategory, path: String)] = []

        // .preferences
        candidates.append((.preferences, home + "/Library/Preferences/" + bundleID + ".plist"))

        // .preferencesByHost: every file in .../ByHost starting with "<bundleID>."
        let byHostDir = home + "/Library/Preferences/ByHost"
        for name in directoryEntries(at: byHostDir, fileManager: fileManager)
        where name.hasPrefix(bundleID + ".") {
            candidates.append((.preferencesByHost, byHostDir + "/" + name))
        }

        // .container: the canonical container, plus any entry "<bundleID>.*"
        candidates.append((.container, home + "/Library/Containers/" + bundleID))
        let containersDir = home + "/Library/Containers"
        for name in directoryEntries(at: containersDir, fileManager: fileManager)
        where name.hasPrefix(bundleID + ".") {
            candidates.append((.container, containersDir + "/" + name))
        }

        // .groupContainer: entries matching "<teamID>." (if team known) OR
        // containing the bundle ID anywhere in their name.
        let groupContainersDir = home + "/Library/Group Containers"
        let teamPrefix: String? = {
            guard let teamID, !teamID.isEmpty else { return nil }
            return teamID + "."
        }()
        for name in directoryEntries(at: groupContainersDir, fileManager: fileManager) {
            let matchesTeam = teamPrefix.map { name.hasPrefix($0) } ?? false
            let matchesBundle = name.contains(bundleID)
            if matchesTeam || matchesBundle {
                candidates.append((.groupContainer, groupContainersDir + "/" + name))
            }
        }

        // .caches
        candidates.append((.caches, home + "/Library/Caches/" + bundleID))

        // .applicationSupport: by bundle ID, and (optionally) by app name.
        candidates.append((.applicationSupport, home + "/Library/Application Support/" + bundleID))
        if let appName {
            candidates.append((.applicationSupport, home + "/Library/Application Support/" + appName))
        }

        // .savedState
        candidates.append((.savedState, home + "/Library/Saved Application State/" + bundleID + ".savedState"))

        // .httpStorages: the directory and the legacy binary cookies file.
        candidates.append((.httpStorages, home + "/Library/HTTPStorages/" + bundleID))
        candidates.append((.httpStorages, home + "/Library/HTTPStorages/" + bundleID + ".binarycookies"))

        // .webKit
        candidates.append((.webKit, home + "/Library/WebKit/" + bundleID))

        // .cookies
        candidates.append((.cookies, home + "/Library/Cookies/" + bundleID + ".binarycookies"))

        // .logs: by bundle ID, and (optionally) by app name.
        candidates.append((.logs, home + "/Library/Logs/" + bundleID))
        if let appName {
            candidates.append((.logs, home + "/Library/Logs/" + appName))
        }

        // .launchAgents: the canonical plist, plus any entry starting with the
        // bundle ID.
        candidates.append((.launchAgents, home + "/Library/LaunchAgents/" + bundleID + ".plist"))
        let launchAgentsDir = home + "/Library/LaunchAgents"
        for name in directoryEntries(at: launchAgentsDir, fileManager: fileManager)
        where name.hasPrefix(bundleID) {
            candidates.append((.launchAgents, launchAgentsDir + "/" + name))
        }

        // Resolve each candidate that exists into a DataLocation, de-duplicating
        // by path (a path may be produced by more than one rule).
        var seenPaths = Set<String>()
        var locations: [DataLocation] = []
        for candidate in candidates {
            guard seenPaths.insert(candidate.path).inserted else { continue }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
                continue
            }
            let dir = isDirectory.boolValue
            let size = dir
                ? directorySize(at: candidate.path, fileManager: fileManager)
                : fileSize(at: candidate.path, fileManager: fileManager)

            locations.append(
                DataLocation(
                    category: candidate.category,
                    path: candidate.path,
                    exists: true,
                    isDirectory: dir,
                    sizeBytes: size
                )
            )
        }

        // Sort by category order, then by descending size.
        let categoryOrder: [DataCategory: Int] = Dictionary(
            uniqueKeysWithValues: DataCategory.allCases.enumerated().map { ($1, $0) }
        )
        locations.sort { lhs, rhs in
            let lo = categoryOrder[lhs.category] ?? Int.max
            let ro = categoryOrder[rhs.category] ?? Int.max
            if lo != ro { return lo < ro }
            return lhs.sizeBytes > rhs.sizeBytes
        }

        return locations
    }

    // MARK: - File-system helpers

    /// Returns the immediate entry names of `path`, or an empty array if the
    /// directory does not exist or cannot be read.
    private static func directoryEntries(at path: String, fileManager: FileManager) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: path)) ?? []
    }

    /// Logical (allocated where available) size of a single file, in bytes.
    private static func fileSize(at path: String, fileManager: FileManager) -> Int64 {
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
            if let allocated = values.totalFileAllocatedSize {
                return Int64(allocated)
            }
            if let logical = values.fileSize {
                return Int64(logical)
            }
        }
        // Fallback to the classic attribute lookup.
        if let attrs = try? fileManager.attributesOfItem(atPath: path),
           let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return 0
    }

    /// Recursively sums the sizes of every regular file beneath `path`.
    private static func directorySize(at path: String, fileManager: FileManager) -> Int64 {
        let baseURL = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: baseURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true } // keep enumerating past unreadable entries
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            // Only count regular files; directories/symlinks contribute via their
            // contained files.
            guard values.isRegularFile == true else { continue }
            if let allocated = values.totalFileAllocatedSize {
                total += Int64(allocated)
            } else if let logical = values.fileSize {
                total += Int64(logical)
            }
        }
        return total
    }
}
