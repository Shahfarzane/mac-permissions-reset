import Foundation

/// Everything known about one app: identity, signing, what it declares it needs,
/// what it has actually been granted, its on-disk footprint, and keychain hints.
public struct AppReport: Sendable, Codable {
    public let app: AppInfo
    public let signing: SigningInfo
    public let declared: [DeclaredPermission]
    public let grants: [TCCGrant]
    public let dataLocations: [DataLocation]
    public let keychainItems: [KeychainItem]

    public var totalDataSize: Int64 {
        dataLocations.reduce(0) { $0 + $1.sizeBytes }
    }

    public init(
        app: AppInfo,
        signing: SigningInfo,
        declared: [DeclaredPermission],
        grants: [TCCGrant],
        dataLocations: [DataLocation],
        keychainItems: [KeychainItem]
    ) {
        self.app = app
        self.signing = signing
        self.declared = declared
        self.grants = grants
        self.dataLocations = dataLocations
        self.keychainItems = keychainItems
    }
}

/// High-level facade composing the AppResetKit modules. This is the single entry
/// point both the CLI and the GUI use; it never touches the main actor and runs
/// blocking work off the caller's executor via the underlying modules.
public struct AppResetService: Sendable {
    private let enumerator: AppEnumerator
    private let tcc: TCCDatabase
    private let entitlements: EntitlementsReader
    private let scanner: DataLocationScanner
    private let keychainScanner: KeychainScanner
    private let engine: ResetEngine
    private let environment: AppEnvironment

    public init() {
        let runner = ProcessRunner()
        let tcc = TCCDatabase()
        self.enumerator = AppEnumerator(runner: runner)
        self.tcc = tcc
        self.entitlements = EntitlementsReader(runner: runner)
        self.scanner = DataLocationScanner()
        self.keychainScanner = KeychainScanner(runner: runner)
        self.engine = ResetEngine(runner: runner)
        self.environment = AppEnvironment(tcc: tcc, runner: runner)
    }

    // MARK: - Discovery

    public func listApps(includeSystem: Bool) async -> [AppInfo] {
        await enumerator.allApps(includeSystem: includeSystem)
    }

    public func resolve(_ query: String, includeSystem: Bool = true) async throws -> AppInfo {
        try await enumerator.resolve(query, includeSystem: includeSystem)
    }

    // MARK: - Inspection

    public func signingInfo(for app: AppInfo) async -> SigningInfo {
        await enumerator.signingInfo(for: app)
    }

    public func declaredPermissions(for app: AppInfo) async -> [DeclaredPermission] {
        await entitlements.declaredPermissions(for: app)
    }

    public func grants(for app: AppInfo) async -> [TCCGrant] {
        await tcc.grants(forBundleID: app.bundleID)
    }

    public func dataLocations(for app: AppInfo) async -> [DataLocation] {
        let signing = await enumerator.signingInfo(for: app)
        return await scanner.scan(bundleID: app.bundleID, appName: app.name, teamID: signing.teamID)
    }

    public func keychainItems(for app: AppInfo) async -> [KeychainItem] {
        await keychainScanner.items(forBundleID: app.bundleID, appName: app.name)
    }

    /// Full report, gathering the independent pieces concurrently.
    public func report(for app: AppInfo, includeKeychain: Bool = true) async -> AppReport {
        let signing = await enumerator.signingInfo(for: app)
        async let declared = entitlements.declaredPermissions(for: app)
        async let grants = tcc.grants(forBundleID: app.bundleID)
        async let data = scanner.scan(bundleID: app.bundleID, appName: app.name, teamID: signing.teamID)

        let keychain: [KeychainItem]
        if includeKeychain {
            keychain = await keychainScanner.items(forBundleID: app.bundleID, appName: app.name)
        } else {
            keychain = []
        }

        return AppReport(
            app: app,
            signing: signing,
            declared: await declared,
            grants: await grants,
            dataLocations: await data,
            keychainItems: keychain
        )
    }

    // MARK: - Environment

    public func hasFullDiskAccess() -> Bool {
        environment.hasFullDiskAccess()
    }

    public func diagnostics() async -> Diagnostics {
        let apps = await enumerator.allApps(includeSystem: true)
        return environment.diagnostics(appCount: apps.count)
    }

    // MARK: - Reset

    private func resetItems(
        for app: AppInfo,
        categories: [ResetCategory],
        options: ResetOptions
    ) async -> [ResetItem] {
        let signing = await enumerator.signingInfo(for: app)
        async let grants = tcc.grants(forBundleID: app.bundleID)
        async let data = scanner.scan(bundleID: app.bundleID, appName: app.name, teamID: signing.teamID)

        let keychain: [KeychainItem]
        if categories.contains(.keychain) {
            keychain = await keychainScanner.items(forBundleID: app.bundleID, appName: app.name)
        } else {
            keychain = []
        }

        return engine.plan(
            app: app,
            categories: categories,
            dataLocations: await data,
            grants: await grants,
            keychainItems: keychain,
            options: options
        )
    }

    /// The operations a reset would perform, without executing them.
    public func plan(
        for app: AppInfo,
        categories: [ResetCategory],
        options: ResetOptions
    ) async -> [ResetItem] {
        await resetItems(for: app, categories: categories, options: options)
    }

    /// Execute a reset. Honors `options.dryRun` (no side effects, everything reported as skipped).
    public func reset(
        _ app: AppInfo,
        categories: [ResetCategory],
        options: ResetOptions
    ) async -> [ResetResult] {
        let items = await resetItems(for: app, categories: categories, options: options)
        return await engine.execute(items, options: options)
    }

    /// Execute a previously-computed plan (e.g. one shown to the user for confirmation).
    public func execute(_ items: [ResetItem], options: ResetOptions) async -> [ResetResult] {
        await engine.execute(items, options: options)
    }

    /// Moves previously-trashed items back to their original locations.
    /// Returns the number successfully restored.
    public func restoreFromTrash(_ items: [TrashedItem]) async -> Int {
        await Offload.run {
            let fm = FileManager.default
            var restored = 0
            for item in items {
                let src = URL(fileURLWithPath: item.trashedPath)
                let dest = URL(fileURLWithPath: item.originalPath)
                guard fm.fileExists(atPath: src.path) else { continue }
                do {
                    try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: dest.path) {
                        try fm.removeItem(at: dest)
                    }
                    try fm.moveItem(at: src, to: dest)
                    restored += 1
                } catch {
                    continue
                }
            }
            return restored
        }
    }
}
