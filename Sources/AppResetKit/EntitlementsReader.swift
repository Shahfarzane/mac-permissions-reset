import Foundation

/// Reads the privacy-relevant permissions an application *declares* about itself.
///
/// Three independent sources are merged into a single, de-duplicated list:
/// 1. `*UsageDescription` strings in the bundle's `Info.plist` (the purpose
///    strings macOS shows in TCC consent prompts).
/// 2. App Sandbox / hardened-runtime entitlements (`com.apple.security.*`)
///    that are present and set to boolean `true`.
/// 3. The private `com.apple.private.tcc.allow` (and `.overridable`)
///    entitlement, which pre-grants TCC services to first-party software.
///
/// Everything is best-effort: a missing plist, an unsigned binary, or a
/// malformed entitlement blob yields fewer results rather than an error.
public struct EntitlementsReader: Sendable {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Collects every permission `app` declares, combining usage-description
    /// purpose strings, sandbox entitlements, and pre-granted TCC services.
    ///
    /// This method never throws; on any failure it simply contributes nothing
    /// from the offending source. Results are de-duplicated by source+key and
    /// sorted by friendly name.
    public func declaredPermissions(for app: AppInfo) async -> [DeclaredPermission] {
        var results: [DeclaredPermission] = []

        results.append(contentsOf: await usageDescriptions(for: app))

        let entitlements = await self.entitlements(for: app)
        results.append(contentsOf: entitlementPermissions(from: entitlements))
        results.append(contentsOf: tccAllowPermissions(from: entitlements))

        // De-duplicate by (source.rawValue + rawKey), preserving first seen.
        var seen = Set<String>()
        var unique: [DeclaredPermission] = []
        unique.reserveCapacity(results.count)
        for permission in results {
            let identity = permission.source.rawValue + permission.rawKey
            if seen.insert(identity).inserted {
                unique.append(permission)
            }
        }

        return unique.sorted {
            $0.friendlyName.localizedCaseInsensitiveCompare($1.friendlyName) == .orderedAscending
        }
    }

    // MARK: - Source 1: Usage descriptions

    /// Reads `Info.plist` and emits a permission for each `*UsageDescription`
    /// key whose value is a non-empty purpose string.
    private func usageDescriptions(for app: AppInfo) async -> [DeclaredPermission] {
        let plistPath = (app.path as NSString)
            .appendingPathComponent("Contents/Info.plist")

        return await Offload.run {
            guard let data = FileManager.default.contents(atPath: plistPath),
                  let plist = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil),
                  let dict = plist as? [String: Any]
            else {
                return []
            }

            var permissions: [DeclaredPermission] = []
            for (key, value) in dict {
                guard key.hasSuffix("UsageDescription"),
                      let description = value as? String
                else { continue }

                permissions.append(
                    DeclaredPermission(
                        rawKey: key,
                        friendlyName: TCCServiceCatalog.friendlyName(forUsageDescriptionKey: key),
                        source: .usageDescription,
                        detail: description,
                        tccService: TCCServiceCatalog.service(forUsageDescriptionKey: key)
                    )
                )
            }
            return permissions
        }
    }

    // MARK: - Sources 2 & 3: Code-signing entitlements

    /// Extracts the entitlements dictionary by shelling out to `codesign`.
    ///
    /// `codesign -d --entitlements :-` prints the entitlements as an XML plist
    /// on stdout (with an unrelated deprecation warning on stderr). Returns an
    /// empty dictionary if the binary is unsigned or has no entitlements.
    private func entitlements(for app: AppInfo) async -> [String: Any] {
        guard let result = try? await runner.run(
            "codesign", ["-d", "--entitlements", ":-", app.path]
        ) else {
            return [:]
        }

        // The plist may arrive on stdout (typical) or, depending on flags and
        // tooling, occasionally on stderr — try both.
        for candidate in [result.stdout, result.stderr] {
            guard let dict = Self.parseEntitlements(candidate) else { continue }
            return dict
        }
        return [:]
    }

    /// Parses an entitlements plist string (XML or binary) into a dictionary.
    private static func parseEntitlements(_ text: String) -> [String: Any]? {
        // Locate the plist payload; codesign may prefix warning text.
        guard let range = text.range(of: "<?xml") ?? text.range(of: "bplist") else {
            return nil
        }
        let payload = String(text[range.lowerBound...])
        guard let data = payload.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil),
              let dict = plist as? [String: Any]
        else {
            return nil
        }
        return dict
    }

    /// Emits a permission for each `com.apple.security.*` entitlement set to `true`.
    private func entitlementPermissions(from dict: [String: Any]) -> [DeclaredPermission] {
        var permissions: [DeclaredPermission] = []
        for (key, value) in dict {
            guard key.hasPrefix("com.apple.security."),
                  let flag = value as? Bool, flag
            else { continue }

            permissions.append(
                DeclaredPermission(
                    rawKey: key,
                    friendlyName: friendlyEntitlementName(key),
                    source: .entitlement,
                    detail: nil,
                    tccService: TCCServiceCatalog.service(forEntitlement: key)
                )
            )
        }
        return permissions
    }

    /// Emits a permission for each TCC service identifier listed under the
    /// private `tcc.allow` (and `.overridable`) entitlements.
    private func tccAllowPermissions(from dict: [String: Any]) -> [DeclaredPermission] {
        let keys = [
            "com.apple.private.tcc.allow",
            "com.apple.private.tcc.allow.overridable",
        ]

        var permissions: [DeclaredPermission] = []
        for key in keys {
            guard let raw = dict[key] else { continue }
            // Accept [String] or a heterogeneous [Any] containing strings.
            let identifiers: [String]
            if let strings = raw as? [String] {
                identifiers = strings
            } else if let array = raw as? [Any] {
                identifiers = array.compactMap { $0 as? String }
            } else {
                continue
            }

            for identifier in identifiers {
                permissions.append(
                    DeclaredPermission(
                        rawKey: identifier,
                        friendlyName: TCCServiceCatalog.friendlyName(for: identifier),
                        source: .tccAllow,
                        detail: nil,
                        tccService: identifier
                    )
                )
            }
        }
        return permissions
    }

    // MARK: - Entitlement naming

    /// Maps a `com.apple.security.*` entitlement key to a human-readable name,
    /// falling back to a humanized form of the suffix for unknown keys.
    private func friendlyEntitlementName(_ key: String) -> String {
        let map: [String: String] = [
            "com.apple.security.network.client": "Network (Outgoing)",
            "com.apple.security.network.server": "Network (Incoming)",
            "com.apple.security.files.user-selected.read-write": "User-Selected Files",
            "com.apple.security.files.user-selected.read-only": "User-Selected Files (Read-Only)",
            "com.apple.security.files.downloads.read-write": "Downloads Folder",
            "com.apple.security.device.camera": "Camera",
            "com.apple.security.device.microphone": "Microphone",
            "com.apple.security.device.audio-input": "Microphone",
            "com.apple.security.device.bluetooth": "Bluetooth",
            "com.apple.security.device.usb": "USB",
            "com.apple.security.personal-information.addressbook": "Contacts",
            "com.apple.security.personal-information.calendars": "Calendar",
            "com.apple.security.personal-information.location": "Location",
            "com.apple.security.personal-information.photos-library": "Photos",
            "com.apple.security.automation.apple-events": "Automation (Apple Events)",
            "com.apple.security.print": "Printing",
        ]

        if let known = map[key] {
            return known
        }

        // Fallback: strip the prefix and humanize the remainder.
        let prefix = "com.apple.security."
        let suffix = key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key
        let words = suffix
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let humanized = words.joined(separator: " ")
        return humanized.isEmpty ? key : humanized
    }
}
