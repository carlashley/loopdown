//// ContentCoordinator.swift
// loopdown
//
// Created on 27/1/2026
//

import Foundation
import LoopdownCore
import LoopdownInfrastructure


// MARK: - Coordinator
public enum ContentCoordinator {

    public enum Mode: Sendable {
        case download
        case deploy
    }

    /// Common entry point used by both `download` and `deploy` CLI commands.
    ///
    /// - Note:
    ///   - `selectedApps`: empty means "all installed apps that loopdown supports".
    ///   - `includeRequired` / `includeOptional` are already validated by the CLI.
    ///   - `appPolicies`: per-app overrides for `includeRequired`/`includeOptional` under
    ///     `--managed`. Empty (the default) means use the global flags for every app.
    ///   - `libraryDestURL`: destination root for modern Logic Pro 12+ / MainStage 4+ content.
    ///     Used for receipt plist lookup (install-state detection) and as the `aa extract -d`
    ///     target. Also passed to `InstalledApplicationResolver` so `AudioApplication` can
    ///     read receipt plists at init time.
    ///   - `destDir` is used for `download` mode output placement.
    ///   - `deploy` downloads into a managed staging directory and installs from there.
    ///   - `skipSignatureCheck`: when false (default), legacy `.pkg` packages are verified as
    ///     signed Apple software before being saved/installed. Modern `.aar` packages are
    ///     never `.pkg` files and the signature check is always skipped for them regardless
    ///     of this flag.
    ///   - `cacheServer` and `mirrorServer` apply to both legacy and modern packages.
    ///     For modern packages, the cache/mirror server replaces the Apple CDN base URL;
    ///     when neither is configured, `modernContentBaseURL` is used directly.
    public static func run(
        mode: Mode,
        selectedApps: [ConcreteApp],
        includeRequired: Bool,
        includeOptional: Bool,
        appPolicies: [AppContentPolicy] = [],
        libraryDestURL: URL,
        destDir: String,
        forceDeploy: Bool,
        skipSignatureCheck: Bool,
        cacheServer: URL?,
        mirrorServer: URL?,
        dryRun: Bool,
        verboseInstall: Bool = false,
        logger: CoreLogger
    ) async throws {

        // 1) Resolve installed apps and filter by CLI selection (if any).
        let installed = Array(
            InstalledApplicationResolver.resolveInstalled(
                libraryDestURL: libraryDestURL,
                logger: logger
            )
        )

        let targetApps: [AudioApplication] = {
            guard !selectedApps.isEmpty else { return installed }
            return installed.filter { app in
                guard let c = app.concreteApp else { return false }
                return selectedApps.contains(c)
            }
        }()

        if targetApps.isEmpty {
            logger.notice("No supported installed applications found (or none matched the requested selection).")
            return
        }

        let downloader = DownloadClient(maxRedirects: 5)

        // 2) Select packages based on mode.
        switch mode {
        case .download:
            try await runDownload(
                apps: targetApps,
                includeRequired: includeRequired,
                includeOptional: includeOptional,
                destDir: destDir,
                skipSignatureCheck: skipSignatureCheck,
                cacheServer: cacheServer,
                mirrorServer: mirrorServer,
                dryRun: dryRun,
                logger: logger,
                downloader: downloader
            )

        case .deploy:
            try await runDeploy(
                apps: targetApps,
                includeRequired: includeRequired,
                includeOptional: includeOptional,
                appPolicies: appPolicies,
                libraryDestURL: libraryDestURL,
                forceDeploy: forceDeploy,
                skipSignatureCheck: skipSignatureCheck,
                cacheServer: cacheServer,
                mirrorServer: mirrorServer,
                dryRun: dryRun,
                verboseInstall: verboseInstall,
                logger: logger,
                downloader: downloader
            )
        }
    }
}

// MARK: - Download mode
private extension ContentCoordinator {

    static func runDownload(
        apps: [AudioApplication],
        includeRequired: Bool,
        includeOptional: Bool,
        destDir: String,
        skipSignatureCheck: Bool,
        cacheServer: URL?,
        mirrorServer: URL?,
        dryRun: Bool,
        logger: CoreLogger,
        downloader: DownloadClient
    ) async throws {

        // For logging, use the legacy base URL as the representative server.
        // The actual per-package URL is determined in packageRemoteURL.
        let baseURL = effectiveBaseURL(cacheServer: cacheServer, mirrorServer: mirrorServer)
        logger.notice("Downloading from \(baseURL.absoluteString) and saving content to \(destDir)")

        // Merge packages across all selected apps (no per-app policy in download mode).
        let pkgs = mergePackagesAcrossApps(
            apps: apps,
            includeRequired: includeRequired,
            includeOptional: includeOptional,
            forceDeploy: false,
            debugLog: nil
        )

        if pkgs.isEmpty {
            logger.notice("No packages selected.")
            return
        }

        // Disk space check: download sizes only.
        let requiredBytes = pkgs.reduce(Int64(0)) { $0 + $1.downloadSize.raw }
        let checkPath = FileManager.default.temporaryDirectory.path
        let freeBytes = try filesystemFreeBytes(atPath: checkPath)

        logger.debug("Free bytes at '\(checkPath)': \(ByteSize(freeBytes))")

        let total = pkgs.count

        if dryRun {
            for (idx, pkg) in pkgs.enumerated() {
                logger.info("\(counter(idx + 1, of: total)) - download: \(pkg.name) (\(pkg.downloadSize))")
            }
            logger.notice(dryRunDownloadSummary(for: pkgs))
            let passed = freeBytes >= requiredBytes
            logger.notice(dryRunDiskSpaceSummary(required: requiredBytes, available: freeBytes, passed: passed))
            return
        }

        if freeBytes < requiredBytes {
            throw ContentCoordinatorError.insufficientDiskSpace(
                required: requiredBytes,
                available: freeBytes,
                path: checkPath
            )
        }

        for (idx, pkg) in pkgs.enumerated() {
            let n = idx + 1

            let remoteURL = packageRemoteURL(
                pkg: pkg,
                cacheServer: cacheServer,
                mirrorServer: mirrorServer
            )
            let destURL = destinationFileURL(destDir: destDir, pkg: pkg)

            logger.info("\(counter(n, of: total)) - downloading: \(pkg.name) (\(pkg.downloadSize))")
            logger.fileOnly("\(counter(n, of: total)) - url: \(remoteURL.absoluteString)")

            let tempURL = try await downloader.downloadTempFile(from: remoteURL) { prog in
                let pct = Int(prog.fractionCompleted * 100)
                logger.debug("progress \(pkg.name): \(pct)% (\(ByteSize(prog.bytesWritten))/\(ByteSize(prog.totalBytesExpected)))")
            }

            // Signature check applies to legacy (.pkg) packages only.
            // Modern (.aar) packages are never Apple-signed packages; skip unconditionally.
            if pkg.isLegacy && !skipSignatureCheck {
                guard PackageSignatureChecker.isSignedAppleSoftware(
                    pkgURL: tempURL,
                    debugLog: logger.debug
                ) else {
                    try? FileManager.default.removeItem(at: tempURL)
                    logger.error("\(counter(n, of: total)) - signature check failed, discarding: \(pkg.name)")
                    continue
                }
            }

            try moveReplacingIfExists(from: tempURL, to: destURL)
            logger.info("\(counter(n, of: total)) - saved: \(pkg.name)")
        }
    }
}

// MARK: - Deploy mode
private extension ContentCoordinator {

    static func runDeploy(
        apps: [AudioApplication],
        includeRequired: Bool,
        includeOptional: Bool,
        appPolicies: [AppContentPolicy],
        libraryDestURL: URL,
        forceDeploy: Bool,
        skipSignatureCheck: Bool,
        cacheServer: URL?,
        mirrorServer: URL?,
        dryRun: Bool,
        verboseInstall: Bool,
        logger: CoreLogger,
        downloader: DownloadClient
    ) async throws {

        logger.debug("forceDeploy: \(forceDeploy)")
        logger.debug("libraryDestURL: \(libraryDestURL.path)")
        if let cacheServer  { logger.debug("cacheServer: \(cacheServer.absoluteString)") }
        if let mirrorServer { logger.debug("mirrorServer: \(mirrorServer.absoluteString)") }

        let baseURL = effectiveBaseURL(cacheServer: cacheServer, mirrorServer: mirrorServer)
        logger.notice("Downloading from \(baseURL.absoluteString) and installing content")

        // 1) Merge packages across apps, filtering by install state.
        let pending = mergePackagesAcrossApps(
            apps: apps,
            includeRequired: includeRequired,
            includeOptional: includeOptional,
            appPolicies: appPolicies,
            forceDeploy: forceDeploy,
            debugLog: logger.debug
        )

        if pending.isEmpty {
            logger.notice("No packages selected for deploy.")
            return
        }

        // 2) Free space check against pending packages only.
        let totalDownload  = pending.reduce(Int64(0)) { $0 + $1.downloadSize.raw }
        let totalInstalled = pending.reduce(Int64(0)) { $0 + $1.installedSize.raw }
        let requiredBytes  = totalDownload + totalInstalled

        let checkPath = FileManager.default.temporaryDirectory.path
        let freeBytes = try filesystemFreeBytes(atPath: checkPath)

        logger.debug("Free bytes at '\(checkPath)': \(ByteSize(freeBytes))")

        // 3) Dry-run: list packages then print summaries.
        if dryRun {
            listPackagesForDryRunDeploy(pending, logger: logger)
            logger.notice(dryRunDownloadSummary(for: pending))
            logger.notice(dryRunInstallSummary(for: pending))
            let passed = freeBytes >= requiredBytes
            logger.notice(dryRunDiskSpaceSummary(required: requiredBytes, available: freeBytes, passed: passed))
            return
        }

        if freeBytes < requiredBytes {
            throw ContentCoordinatorError.insufficientDiskSpace(
                required: requiredBytes,
                available: freeBytes,
                path: checkPath
            )
        }

        // 4) Create staging directory and install signal handlers for cleanup.
        let staging = try TemporaryDirectory()

        let signalCleanup = SignalCleanup {
            staging.cleanup()
        }
        signalCleanup.install()

        defer {
            signalCleanup.uninstall()
            staging.cleanup()
        }

        // 5) Download into staging, verify signature (legacy only), then install.
        let total = pending.count
        for (idx, pkg) in pending.enumerated() {
            let n = idx + 1
            let remoteURL = packageRemoteURL(
                pkg: pkg,
                cacheServer: cacheServer,
                mirrorServer: mirrorServer
            )

            logger.info("\(counter(n, of: total)) - downloading: \(pkg.name)")
            logger.fileOnly("\(counter(n, of: total)) - url: \(remoteURL.absoluteString)")

            let tempURL = try await downloader.downloadTempFile(from: remoteURL) { prog in
                let pct = Int(prog.fractionCompleted * 100)
                logger.debug("progress \(pkg.name): \(pct)%")
            }

            let stagedURL = staging.url.appendingPathComponent(pkg.name)
            try FileManager.default.moveItem(at: tempURL, to: stagedURL)

            // Signature check applies to legacy (.pkg) packages only.
            if pkg.isLegacy && !skipSignatureCheck {
                guard PackageSignatureChecker.isSignedAppleSoftware(
                    pkgURL: stagedURL,
                    debugLog: logger.debug
                ) else {
                    logger.error("\(counter(n, of: total)) - signature check failed, skipping install: \(pkg.name)")
                    continue
                }
            }

            let label  = counter(n, of: total)
            let indent = String(repeating: " ", count: label.count + 3)

            if pkg.isLegacy {
                // Legacy: install via /usr/sbin/installer
                do {
                    try PackageInstaller.install(
                        pkgURL: stagedURL,
                        packageName: pkg.name,
                        verbose: verboseInstall,
                        debugLog: logger.debug,
                        errorLog: logger.error
                    )
                    logger.notice("\(indent)installed: \(pkg.name)")
                } catch {
                    logger.error("\(indent)failed to install: \(pkg.name) (\(error))")
                }
            } else {
                // Modern: extract via /usr/bin/aa extract -d <libraryDestURL> -i <archive>
                do {
                    try AARExtractor.extract(
                        packageURL: stagedURL,
                        packageName: pkg.name,
                        libraryDestURL: libraryDestURL,
                        debugLog: logger.debug,
                        errorLog: logger.error
                    )
                    logger.notice("\(indent)extracted: \(pkg.name)")
                } catch {
                    logger.error("\(indent)failed to extract: \(pkg.name) (\(error))")
                }
            }
        }
    }

    static func listPackagesForDryRunDeploy(
        _ pkgs: [AudioContentPackage],
        logger: CoreLogger
    ) {
        let total = pkgs.count
        for (idx, pkg) in pkgs.enumerated() {
            logger.info("\(counter(idx + 1, of: total)) - download+install: \(pkg.name) (\(pkg.downloadSize) dl, \(pkg.installedSize) installed)")
        }
    }
}

// MARK: - Dry-run summary helpers
private extension ContentCoordinator {

    static func dryRunDownloadSummary(for pkgs: [AudioContentPackage]) -> String {
        let required = pkgs.filter { $0.mandatory }
        let optional = pkgs.filter { !$0.mandatory }

        let reqSize = required.reduce(Int64(0)) { $0 + $1.downloadSize.raw }
        let optSize = optional.reduce(Int64(0)) { $0 + $1.downloadSize.raw }

        var parts: [String] = []
        if !required.isEmpty {
            parts.append("\(required.count) required: \(ByteSize(reqSize).description)")
        }
        if !optional.isEmpty {
            parts.append("\(optional.count) optional: \(ByteSize(optSize).description)")
        }

        let breakdown = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "Total download \(pkgs.count) package\(pkgs.count == 1 ? "" : "s")\(breakdown)"
    }

    static func dryRunInstallSummary(for pkgs: [AudioContentPackage]) -> String {
        let required = pkgs.filter { $0.mandatory }
        let optional = pkgs.filter { !$0.mandatory }

        let reqSize   = required.reduce(Int64(0)) { $0 + $1.installedSize.raw }
        let optSize   = optional.reduce(Int64(0)) { $0 + $1.installedSize.raw }
        let totalSize = reqSize + optSize

        var parts: [String] = []
        if !required.isEmpty {
            parts.append("\(required.count) required: \(ByteSize(reqSize).description)")
        }
        if !optional.isEmpty {
            parts.append("\(optional.count) optional: \(ByteSize(optSize).description)")
        }

        let breakdown = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "Total install size \(ByteSize(totalSize).description)\(breakdown)"
    }

    static func dryRunDiskSpaceSummary(required: Int64, available: Int64, passed: Bool) -> String {
        let status = passed ? "passed" : "failed"
        return "Required disk space check: \(status) (\(ByteSize(required)) required, \(ByteSize(available)) available)"
    }
}

// MARK: - Package selection/merge helpers
private extension ContentCoordinator {

    /// Determine whether a package needs to be downloaded and installed.
    ///
    /// **Legacy packages** — same logic as before:
    ///   1. No `fileCheck` paths → assume needs install.
    ///   2. No `fileCheck` path exists on disk → not installed.
    ///   3. Paths exist, no remote version → treat as current.
    ///   4. Paths exist, remote version known → pkgutil receipt comparison.
    ///
    /// **Modern packages** — install state is determined solely by `fileCheck` paths:
    ///   - `fileCheck` paths come from the receipt plist; absence of a receipt means
    ///     the package is not installed (fileCheck will be empty).
    ///   - All paths must exist for the package to be considered installed (Python
    ///     `has_sentinel_files` for modern uses `check_all=True`).
    ///   - No `pkgutil` version comparison is performed for modern packages.
    static func packageNeedsInstall(
        _ pkg: AudioContentPackage,
        debugLog: ((String) -> Void)?
    ) -> Bool {
        if pkg.isLegacy {
            return legacyPackageNeedsInstall(pkg, debugLog: debugLog)
        } else {
            return modernPackageNeedsInstall(pkg, debugLog: debugLog)
        }
    }

    static func modernPackageNeedsInstall(
        _ pkg: AudioContentPackage,
        debugLog: ((String) -> Void)?
    ) -> Bool {
        // No receipt → no fileCheck paths → not installed.
        guard !pkg.fileCheck.isEmpty else {
            debugLog?("\(pkg.name): no receipt/fileCheck paths — treating as not installed")
            return true
        }

        // All fileCheck paths must exist (Python modern uses check_all=True).
        let allExist = pkg.fileCheck.allSatisfy { FileManager.default.fileExists(atPath: $0) }
        debugLog?("\(pkg.name): modern install check — all fileCheck paths exist: \(allExist)")
        return !allExist
    }

    static func legacyPackageNeedsInstall(
        _ pkg: AudioContentPackage,
        debugLog: ((String) -> Void)?
    ) -> Bool {
        guard !pkg.fileCheck.isEmpty else {
            debugLog?("\(pkg.name): no fileCheck paths, assuming needs install")
            return true
        }

        let anyPathExists = pkg.fileCheck.contains { FileManager.default.fileExists(atPath: $0) }
        guard anyPathExists else {
            debugLog?("\(pkg.name): not installed (no fileCheck paths found on disk)")
            return true
        }

        guard let remoteVersion = pkg.version else {
            debugLog?("\(pkg.name): installed, no remote version to compare — treating as current")
            return false
        }

        do {
            guard let receipt = try PackageReceipt.loadIfInstalled(
                pkg.packageID,
                debugLog: debugLog
            ) else {
                debugLog?("\(pkg.name): fileCheck paths exist but no pkgutil receipt — reinstalling")
                return true
            }

            guard let localVersion = receipt.version else {
                debugLog?("\(pkg.name): receipt has no version — reinstalling")
                return true
            }

            let upToDate = PackageReceipt.localVersionIsCurrentOrNewer(
                localVersion: localVersion,
                remoteVersion: remoteVersion
            )
            debugLog?("\(pkg.name): local=\(localVersion) remote=\(remoteVersion) upToDate=\(upToDate)")
            return !upToDate

        } catch {
            debugLog?("\(pkg.name): pkgutil error (\(error)) — treating as current")
            return false
        }
    }

    /// Merge packages across all target apps, deduplicating by package ID.
    static func mergePackagesAcrossApps(
        apps: [AudioApplication],
        includeRequired: Bool,
        includeOptional: Bool,
        appPolicies: [AppContentPolicy] = [],
        forceDeploy: Bool,
        debugLog: ((String) -> Void)?
    ) -> [AudioContentPackage] {

        let policyByApp: [ConcreteApp: AppContentPolicy] = appPolicies.reduce(into: [:]) {
            $0[$1.app] = $1
        }

        var byID: [String: AudioContentPackage] = [:]
        var mandatoryIDs = Set<String>()

        for app in apps {
            let policy       = app.concreteApp.flatMap { policyByApp[$0] }
            let wantRequired = policy?.required ?? includeRequired
            let wantOptional = policy?.optional ?? includeOptional

            if wantRequired {
                for pkg in app.mandatory {
                    if !forceDeploy && !packageNeedsInstall(pkg, debugLog: debugLog) { continue }
                    if let existing = byID[pkg.packageID] {
                        if !existing.mandatory { byID[pkg.packageID] = pkg }
                    } else {
                        byID[pkg.packageID] = pkg
                    }
                    mandatoryIDs.insert(pkg.packageID)
                }
            }

            if wantOptional {
                for pkg in app.optional {
                    if mandatoryIDs.contains(pkg.packageID) { continue }
                    if !forceDeploy && !packageNeedsInstall(pkg, debugLog: debugLog) { continue }
                    if byID[pkg.packageID] == nil {
                        byID[pkg.packageID] = pkg
                    }
                }
            }
        }

        return byID.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - Disk space helper
private extension ContentCoordinator {

    static func filesystemFreeBytes(atPath path: String) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
        guard let n = attrs[.systemFreeSize] as? NSNumber else {
            throw ContentCoordinatorError.unableToReadDiskSpace(path: path)
        }
        return n.int64Value
    }
}

// MARK: - Errors
public enum ContentCoordinatorError: Error, CustomStringConvertible {
    case insufficientDiskSpace(required: Int64, available: Int64, path: String)
    case unableToReadDiskSpace(path: String)

    public var description: String {
        switch self {
        case .insufficientDiskSpace(let required, let available, let path):
            return "Insufficient disk space at '\(path)'. Required=\(ByteSize(required)), Available=\(ByteSize(available))"
        case .unableToReadDiskSpace(let path):
            return "Unable to read disk space information for '\(path)'."
        }
    }
}

// MARK: - URL + filesystem helpers
private extension ContentCoordinator {

    /// Effective base URL for all packages (legacy and modern alike).
    ///
    /// Priority: mirrorServer > cacheServer > Apple CDN root.
    ///
    /// The path component distinguishing legacy (`lp10_ms3_content_2016/…`) from modern
    /// (`universal/ContentPacks_3/…`) content is already baked into each package's
    /// `downloadPath`, so the server base is always applied uniformly. This matches
    /// the Python `ctx.server` model after the fix in `_server_mixin.py` / `_download_mixin.py`.
    static func effectiveBaseURL(cacheServer: URL?, mirrorServer: URL?) -> URL {
        mirrorServer
            ?? cacheServer
            ?? LoopdownConstants.Downloads.contentSourceBaseURL
    }

    /// Build the remote download URL for a package.
    ///
    /// The server base is chosen uniformly for both legacy and modern packages.
    /// `pkg.downloadPath` already contains the full relative path:
    ///   - Legacy:  `lp10_ms3_content_2016/<filename>.pkg`
    ///   - Modern:  `universal/ContentPacks_3/<server_path>.aar`
    static func packageRemoteURL(
        pkg: AudioContentPackage,
        cacheServer: URL?,
        mirrorServer: URL?
    ) -> URL {
        let base = effectiveBaseURL(cacheServer: cacheServer, mirrorServer: mirrorServer)
        var url = base
        for part in pkg.downloadPath.split(separator: "/") {
            url.appendPathComponent(String(part))
        }
        return url
    }

    static func destinationFileURL(destDir: String, pkg: AudioContentPackage) -> URL {
        let dir = URL(fileURLWithPath: destDir, isDirectory: true)
        var out = dir
        for part in pkg.downloadPath.split(separator: "/") {
            out.appendPathComponent(String(part))
        }
        return out
    }

    static func ensureParentDirectoryExists(for fileURL: URL) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    static func moveReplacingIfExists(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try ensureParentDirectoryExists(for: dst)
        try fm.moveItem(at: src, to: dst)
    }

    // MARK: - Counter formatting helper

    static func counter(_ n: Int, of total: Int) -> String {
        let width = String(total).count
        return String(format: "%\(width)d of %d", n, total)
    }
}
