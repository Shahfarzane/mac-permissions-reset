import Foundation

/// Discovers installed macOS applications and inspects their bundle metadata
/// and code-signing characteristics.
///
/// `AppEnumerator` is a thin, dependency-injected wrapper around a
/// `ProcessRunner` (for `mdfind` and `codesign`) plus `FileManager`/
/// `PropertyListSerialization` for reading bundle `Info.plist` files. All
/// blocking filesystem work is pushed off the caller's executor via `Offload`.
public struct AppEnumerator: Sendable {

    /// Process runner used to invoke `mdfind` and `codesign`.
    private let runner: ProcessRunner

    /// Creates an enumerator.
    /// - Parameter runner: Process runner used for shelling out. Defaults to a
    ///   fresh `ProcessRunner`.
    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    // MARK: - Bundle metadata

    /// Reads the `Info.plist` of the `.app` bundle at `path` and builds an
    /// `AppInfo`.
    ///
    /// Returns `nil` when the bundle has no readable `Info.plist` or the plist
    /// lacks a `CFBundleIdentifier`. This method is synchronous and performs
    /// blocking disk I/O; callers that need to stay off the current executor
    /// should wrap it (see `allApps`/`resolve`, which already do).
    public func appInfo(atPath path: String) -> AppInfo? {
        let plistPath = (path as NSString)
            .appendingPathComponent("Contents/Info.plist")

        guard let data = FileManager.default.contents(atPath: plistPath) else {
            return nil
        }

        let parsed = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let dict = parsed as? [String: Any] else { return nil }

        // CFBundleIdentifier is mandatory.
        guard let bundleID = (dict["CFBundleIdentifier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !bundleID.isEmpty
        else {
            return nil
        }

        let lastComponent = (path as NSString).lastPathComponent
        let fileBaseName: String = lastComponent.hasSuffix(".app")
            ? String(lastComponent.dropLast(".app".count))
            : lastComponent

        func cleaned(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { return nil }
            return trimmed.hasSuffix(".app") ? String(trimmed.dropLast(".app".count)) : trimmed
        }

        // The Finder-facing (localized) bundle name is what the user actually
        // calls the app, so prefer it over CFBundleName — which is frequently a
        // short/internal product name. E.g. an Electron app whose bundle is
        // `Factory.app` but whose CFBundleName is `factory-desktop`.
        let name = cleaned(FileManager.default.displayName(atPath: path))
            ?? cleaned(dict["CFBundleDisplayName"] as? String)
            ?? cleaned(dict["CFBundleName"] as? String)
            ?? fileBaseName

        let version = dict["CFBundleShortVersionString"] as? String
        let build = dict["CFBundleVersion"] as? String
        let executableName = dict["CFBundleExecutable"] as? String
        let source: AppSource = path.hasPrefix("/System/") ? .system : .user

        return AppInfo(
            bundleID: bundleID,
            name: name,
            version: version,
            build: build,
            path: path,
            executableName: executableName,
            source: source
        )
    }

    // MARK: - Enumeration

    /// Returns every discoverable application, de-duplicated by bundle
    /// identifier and sorted by display name.
    ///
    /// Candidate bundle paths are gathered from Spotlight (`mdfind`) and by
    /// directly listing the well-known application directories, so apps remain
    /// discoverable even when the Spotlight index is unavailable.
    ///
    /// - Parameter includeSystem: When `false`, applications under `/System/`
    ///   (i.e. `AppSource.system`) are excluded from the result.
    public func allApps(includeSystem: Bool = true) async -> [AppInfo] {
        // (a) Spotlight-provided candidates. `mdfind` is already async here.
        var paths: [String] = []
        let query = "kMDItemContentTypeTree == 'com.apple.application-bundle'"
        if let result = try? await runner.run("mdfind", [query]) {
            for line in result.stdout.split(
                separator: "\n",
                omittingEmptySubsequences: true
            ) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasSuffix(".app") { paths.append(trimmed) }
            }
        }

        // (b) Direct directory listings (off the current executor).
        let directoryPaths = await Offload.run {
            Self.scanApplicationDirectories()
        }
        paths.append(contentsOf: directoryPaths)

        // De-duplicate candidate paths while preserving order.
        var seenPaths = Set<String>()
        let uniquePaths = paths.filter { seenPaths.insert($0).inserted }

        // Read each Info.plist off the current executor.
        let infos: [AppInfo] = await Offload.run {
            uniquePaths.compactMap { appInfo(atPath: $0) }
        }

        // De-duplicate by bundle identifier.
        var byBundleID: [String: AppInfo] = [:]
        for info in infos {
            let key = info.bundleID.lowercased()
            if let existing = byBundleID[key] {
                if Self.preferred(existing, over: info) == info {
                    byBundleID[key] = info
                }
            } else {
                byBundleID[key] = info
            }
        }

        var apps = Array(byBundleID.values)
        if !includeSystem {
            apps.removeAll { $0.source == .system }
        }

        apps.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return apps
    }

    /// Lists `.app` entries directly inside the well-known application
    /// directories. Synchronous; intended to be wrapped in `Offload`.
    private static func scanApplicationDirectories() -> [String] {
        let home = NSHomeDirectory()
        let directories = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            home + "/Applications",
        ]

        let fm = FileManager.default
        var results: [String] = []
        for dir in directories {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else {
                continue
            }
            for entry in entries where entry.hasSuffix(".app") {
                results.append((dir as NSString).appendingPathComponent(entry))
            }
        }
        return results
    }

    /// Picks which of two `AppInfo` values for the same bundle identifier to
    /// keep. Prefers a `.user` source over `.system`; otherwise prefers an app
    /// under `/Applications`, then the shorter path.
    private static func preferred(_ a: AppInfo, over b: AppInfo) -> AppInfo {
        if a.source != b.source {
            return a.source == .user ? a : b
        }
        let aTopLevel = a.path.hasPrefix("/Applications/")
        let bTopLevel = b.path.hasPrefix("/Applications/")
        if aTopLevel != bTopLevel {
            return aTopLevel ? a : b
        }
        return a.path.count <= b.path.count ? a : b
    }

    // MARK: - Resolution

    /// Resolves a user-supplied `query` to a single application.
    ///
    /// If `query` looks like a path (contains `/` or ends in `.app`) it is
    /// expanded, made absolute and read directly. Otherwise the query is
    /// matched against the installed app list in priority order: exact bundle
    /// identifier, then exact name, then a name substring (all
    /// case-insensitive).
    ///
    /// - Throws: `AppResetError.appNotFound` when nothing matches, or
    ///   `AppResetError.ambiguousApp` when the matches span more than one
    ///   bundle identifier.
    public func resolve(
        _ query: String,
        includeSystem: Bool = true
    ) async throws -> AppInfo {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Path-style queries are read directly.
        if trimmed.contains("/") || trimmed.hasSuffix(".app") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            let absolute: String
            if (expanded as NSString).isAbsolutePath {
                absolute = expanded
            } else {
                let cwd = FileManager.default.currentDirectoryPath
                absolute = (cwd as NSString)
                    .appendingPathComponent(expanded)
            }
            let standardized = (absolute as NSString).standardizingPath
            if let info = await Offload.run({ appInfo(atPath: standardized) }) {
                return info
            }
            throw AppResetError.appNotFound(query: query)
        }

        // Name / bundle-identifier matching against the full app list.
        let apps = await allApps(includeSystem: true)

        let exactBundle = apps.filter {
            $0.bundleID.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        let matches: [AppInfo]
        if !exactBundle.isEmpty {
            matches = exactBundle
        } else {
            let exactName = apps.filter {
                $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
            }
            if !exactName.isEmpty {
                matches = exactName
            } else {
                matches = apps.filter {
                    $0.name.range(
                        of: trimmed,
                        options: .caseInsensitive
                    ) != nil
                }
            }
        }

        guard !matches.isEmpty else {
            throw AppResetError.appNotFound(query: query)
        }

        let distinctBundleIDs = Set(matches.map { $0.bundleID.lowercased() })
        if distinctBundleIDs.count > 1 {
            let names = matches.map { $0.name }
            throw AppResetError.ambiguousApp(
                query: query,
                matches: Array(names.prefix(8))
            )
        }

        return matches[0]
    }

    // MARK: - Code signing

    /// Inspects the code signature of `app`'s bundle.
    ///
    /// This is best-effort: it never throws and returns `nil` fields where the
    /// information cannot be determined. `codesign` writes its `-dvvv` metadata
    /// to standard error and its `--entitlements` dump to standard output.
    public func signingInfo(for app: AppInfo) async -> SigningInfo {
        var teamID: String?
        var authority: String?
        var isAdHoc = false

        if let meta = try? await runner.run("codesign", ["-dvvv", app.path]) {
            // `-dvvv` metadata is on stderr; check stdout too for robustness.
            let combined = meta.stderr + "\n" + meta.stdout
            for rawLine in combined.split(
                separator: "\n",
                omittingEmptySubsequences: true
            ) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)

                if line.hasPrefix("TeamIdentifier=") {
                    let value = String(line.dropFirst("TeamIdentifier=".count))
                        .trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty,
                       value.caseInsensitiveCompare("not set") != .orderedSame {
                        teamID = value
                    }
                } else if line.hasPrefix("Authority="), authority == nil {
                    // First Authority line is the leaf certificate.
                    let value = String(line.dropFirst("Authority=".count))
                        .trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { authority = value }
                }
            }

            if combined.contains("Signature=adhoc")
                || combined.contains("linker-signed") {
                isAdHoc = true
            }
        }

        let isSandboxed = await sandboxFlag(for: app)

        return SigningInfo(
            teamID: teamID,
            authority: authority,
            isSandboxed: isSandboxed,
            isAdHoc: isAdHoc
        )
    }

    /// Determines whether the bundle declares the App Sandbox entitlement.
    /// Defaults to `false` on any failure to read or parse entitlements.
    private func sandboxFlag(for app: AppInfo) async -> Bool {
        guard let result = try? await runner.run(
            "codesign",
            ["-d", "--entitlements", ":-", app.path]
        ) else {
            return false
        }

        // The entitlements plist is emitted on stdout; fall back to stderr.
        if let value = Self.sandboxValue(fromPlistString: result.stdout) {
            return value
        }
        if let value = Self.sandboxValue(fromPlistString: result.stderr) {
            return value
        }
        return false
    }

    /// Parses an entitlements plist string and returns the boolean value of
    /// `com.apple.security.app-sandbox`, or `nil` when it cannot be determined.
    private static func sandboxValue(fromPlistString string: String) -> Bool? {
        // Trim any leading non-plist noise (e.g. codesign warning lines).
        guard let markerRange = string.range(of: "<?xml") else { return nil }
        let plistText = String(string[markerRange.lowerBound...])
        guard let data = plistText.data(using: .utf8) else { return nil }

        let parsed = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let dict = parsed as? [String: Any] else { return nil }
        return (dict["com.apple.security.app-sandbox"] as? Bool) ?? false
    }
}
