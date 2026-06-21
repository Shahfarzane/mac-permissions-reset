import Foundation

/// Best-effort discovery of macOS Keychain items that *appear* to belong to a
/// given application.
///
/// ## Why this is intentionally limited
/// macOS provides no clean API or CLI to "list every Keychain item owned by a
/// bundle identifier". The `security` command-line tool's `find-generic-password`
/// and `find-internet-password` subcommands each return **only the first match**
/// for a query — there is no "find all" mode short of `dump-keychain`, which
/// requires interactive authorization and dumps the entire keychain. As a result
/// this scanner probes a small set of plausible *service* strings (the bundle ID
/// and, optionally, the app's display name) and reports at most one item per
/// (subcommand, service) probe. Items keyed under service strings we do not guess
/// will be missed. Treat the output as a hint for the user, not an exhaustive
/// inventory.
///
/// ## Safety
/// This type is strictly read-only. It never passes `-g`/`-w` (so password
/// secrets are never fetched), never deletes anything, and never throws — every
/// failure mode resolves to "no items found".
public struct KeychainScanner: Sendable {

    /// Exit code returned by `security` when the requested item is not present.
    private static let notFoundExitCode: Int32 = 44

    private let runner: ProcessRunner

    /// Creates a scanner.
    /// - Parameter runner: Process runner used to shell out to `security`.
    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Discovers Keychain items that plausibly belong to the given app.
    ///
    /// Builds candidate service strings from `bundleID` and (if provided)
    /// `appName`, then probes both generic and internet password stores for each.
    /// Results are de-duplicated by `(kind, service, account)`.
    ///
    /// - Parameters:
    ///   - bundleID: The application's bundle identifier (primary candidate).
    ///   - appName: Optional display name used as an additional candidate.
    /// - Returns: A possibly-empty list of discovered items. Never throws.
    public func items(forBundleID bundleID: String, appName: String?) async -> [KeychainItem] {
        // Build an ordered, de-duplicated set of candidate service strings.
        var candidates: [String] = []
        var seenCandidates = Set<String>()
        for raw in [bundleID, appName].compactMap({ $0 }) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seenCandidates.insert(trimmed).inserted else { continue }
            candidates.append(trimmed)
        }

        var results: [KeychainItem] = []
        var seenItems = Set<DedupeKey>()

        for service in candidates {
            for kind in [KeychainItem.Kind.generic, .internet] {
                guard let item = await probe(service: service, kind: kind) else { continue }
                let key = DedupeKey(kind: item.kind, service: item.service, account: item.account)
                if seenItems.insert(key).inserted {
                    results.append(item)
                }
            }
        }

        return results
    }

    // MARK: - Probing

    /// Runs a single `security find-*-password -s <service>` probe and, on a hit,
    /// parses its metadata into a ``KeychainItem``. Returns `nil` on any miss or
    /// error.
    private func probe(service: String, kind: KeychainItem.Kind) async -> KeychainItem? {
        let subcommand: String
        switch kind {
        case .generic: subcommand = "find-generic-password"
        case .internet: subcommand = "find-internet-password"
        }

        // Deliberately omit -g/-w so secrets are never requested.
        let result: ProcessResult
        do {
            result = try await runner.run("security", [subcommand, "-s", service])
        } catch {
            // A launch failure is treated as "not found" — best effort only.
            return nil
        }

        // Exit code 0 means a match; 44 means not found; anything else we ignore.
        guard result.exitCode == 0 else { return nil }

        // `security` writes the attributes block to stdout or stderr depending on
        // invocation; scan both so we do not miss the metadata.
        let combined = result.stdout + "\n" + result.stderr

        // Guard against an exit-0-but-no-match situation: require an attributes
        // marker before trusting the output.
        guard combined.contains("\"svce\"") || combined.contains("\"acct\"") else {
            return nil
        }

        let parsedService = Self.attributeValue(named: "svce", in: combined)
        let parsedAccount = Self.attributeValue(named: "acct", in: combined)

        return KeychainItem(
            kind: kind,
            service: parsedService ?? service,
            account: parsedAccount ?? ""
        )
    }

    // MARK: - Parsing

    /// Extracts the quoted value from an attribute line of the form
    /// `    "svce"<blob>="some value"`. Returns `nil` when the attribute is
    /// absent or its value is `<NULL>`.
    ///
    /// The scan is line-oriented and tolerant of unknown type tags (`<blob>`,
    /// `<uint32>`, etc.). It correctly handles embedded escaped quotes within the
    /// value by consuming up to the final `"` on the line.
    static func attributeValue(named name: String, in text: String) -> String? {
        let marker = "\"\(name)\""
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard let markerRange = line.range(of: marker) else { continue }

            // Find the `=` that follows the type tag, then the opening quote.
            let afterMarker = line[markerRange.upperBound...]
            guard let equalsRange = afterMarker.range(of: "=") else { continue }
            let valuePart = afterMarker[equalsRange.upperBound...]

            // Value is either `<NULL>` (no value) or a double-quoted string.
            guard let openQuote = valuePart.firstIndex(of: "\"") else {
                // No quoted value (e.g. `<NULL>`).
                return nil
            }
            let inner = valuePart[valuePart.index(after: openQuote)...]
            guard let closeQuote = inner.lastIndex(of: "\"") else { continue }

            let value = String(inner[..<closeQuote])
            return value.isEmpty ? nil : value
        }
        return nil
    }

    // MARK: - De-duplication

    /// Hashable composite key for de-duplicating discovered items.
    private struct DedupeKey: Hashable {
        let kind: KeychainItem.Kind
        let service: String
        let account: String
    }
}
