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
    ///   - `destDir` is used for `download` mode output placement.
    ///   - `deploy` downloads into a managed staging directory and installs from there.
    ///   - `skipSignatureCheck`: when false (default), each downloaded package is verified
    ///     as signed Apple software before being saved/installed.
    public static func run(
        mode: Mode,
        selectedApps: [ConcreteApp],
        includeRequired: Bool,
        includeOptional: Bool,
        appPolicies: [AppContentPolicy] = [],
        destDir: String,
        forceDeploy: Bool,
        skipSignatureCheck: Bool,
        cacheServer: URL?,
        mirrorServer: URL?,
        dryRun: Bool,
        logger: CoreLogger
    ) async throws {

        // 1) Resolve installed apps and filter by CLI selection (if any).
        let installed = Array(InstalledApplicationResolver.resolveInstalled(logger: logger))

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
                forceDeploy: forceDeploy,
                skipSignatureCheck: skipSignatureCheck,
                cacheServer: cacheServer,
                mirrorServer: mirrorServer,
                dryRun: dryRun,
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

        let baseURL = effectiveBaseURL(cacheServer: cacheServer, mirrorServer: mirrorServer)
        logger.notice("Downloading from \(baseURL.absoluteString) and saving content to \(destDir)")

        // Merge packages across all selected apps to avoid downloading duplicates.
        // Download mode has no per-app policy concept — appPolicies is --managed only.
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

        // Disk space check: download sizes only (no install step in download mode).
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

            let remoteURL = packageRemoteURL(baseURL: baseURL, pkg: pkg)
            let destURL = destinationFileURL(destDir: destDir, pkg: pkg)

            logger.info("\(counter(n, of: total)) - downloading: \(pkg.name) (\(pkg.downloadSize))")

            let tempURL = try await downloader.downloadTempFile(from: remoteURL) { prog in
                let pct = Int(prog.fractionCompleted * 100)
                logger.debug("progress \(pkg.name): \(pct)% (\(ByteSize(prog.bytesWritten))/\(ByteSize(prog.totalBytesExpected)))")
            }

            // Verify the downloaded package is signed Apple software before saving.
            if !skipSignatureCheck {
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
        forceDeploy: Bool,
        skipSignatureCheck: Bool,
        cacheServer: URL?,
        mirrorServer: URL?,
        dryRun: Bool,
        logger: CoreLogger,
        downloader: DownloadClient
    ) async throws {

        logger.debug("forceDeploy: \(forceDeploy)")
        if let cacheServer  { logger.debug("cacheServer: \(cacheServer.absoluteString)") }
        if let mirrorServer { logger.debug("mirrorServer: \(mirrorServer.absoluteString)") }

        let baseURL = effectiveBaseURL(cacheServer: cacheServer, mirrorServer: mirrorServer)
        logger.notice("Downloading from \(baseURL.absoluteString) and installing content")

        // 1) Merge packages across apps, filtering by install state per-app (matching Python
        //    behaviour). forceDeploy bypasses the install-state filter so all packages are
        //    included regardless. appPolicies provides per-app required/optional overrides
        //    under --managed; empty means use the global includeRequired/includeOptional.
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
        // NOTE: This checks the filesystem backing URLSession temp directory.
        let totalDownload  = pending.reduce(Int64(0)) { $0 + $1.downloadSize.raw }
        let totalInstalled = pending.reduce(Int64(0)) { $0 + $1.installedSize.raw }
        let requiredBytes  = totalDownload + totalInstalled

        let checkPath = FileManager.default.temporaryDirectory.path
        let freeBytes = try filesystemFreeBytes(atPath: checkPath)

        logger.debug("Free bytes at '\(checkPath)': \(ByteSize(freeBytes))")

        // 3) Dry-run: list packages then print download, install, and disk space summaries.
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

        // 4) Early exit if nothing needs installing (all packages already up to date).
        if pending.isEmpty {
            logger.notice("All packages are already installed.")
            return
        }

        // 5) Create staging directory and install signal handlers for cleanup.
        let staging = try TemporaryDirectory()

        let signalCleanup = SignalCleanup {
            staging.cleanup()
        }
        signalCleanup.install()

        defer {
            signalCleanup.uninstall()
            staging.cleanup()
        }

        // 6) Download into staging, verify signature, then install.
        // Iterate over `pending` directly — it already contains only the packages
        // that need installing, so no further filtering calls are needed here.
        let total = pending.count
        for (idx, pkg) in pending.enumerated() {
            let n = idx + 1
            let remoteURL = packageRemoteURL(baseURL: baseURL, pkg: pkg)

            logger.info("\(counter(n, of: total)) - downloading: \(pkg.name)")

            let tempURL = try await downloader.downloadTempFile(from: remoteURL) { prog in
                let pct = Int(prog.fractionCompleted * 100)
                logger.debug("progress \(pkg.name): \(pct)%")
            }

            // Move the URLSession temp file into the managed staging directory before checking/installing.
            let stagedURL = staging.url.appendingPathComponent(pkg.name)
            try FileManager.default.moveItem(at: tempURL, to: stagedURL)

            // Verify the downloaded package is signed Apple software before installing.
            if !skipSignatureCheck {
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
            do {
                try PackageInstaller.install(
                    pkgURL: stagedURL,
                    packageName: pkg.name,
                    debugLog: logger.debug,
                    errorLog: logger.error
                )
                logger.notice("\(indent)installed: \(pkg.name)")
            } catch {
                logger.error("\(indent)failed to install: \(pkg.name) (\(error))")
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

    /// Summary line for download mode and the download portion of deploy mode.
    ///
    /// Example: "Total download 5 packages (3 required: 120.00MB, 2 optional: 45.00MB)"
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

    /// Summary line for the install portion of deploy mode.
    ///
    /// Example: "Total install size 165.00MB (3 required: 120.00MB, 2 optional: 45.00MB)"
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

    /// Summary line for the disk space check portion of a dry-run.
    ///
    /// Example: "Required disk space check: passed (5.80GB required, 326.54GB available)"
    static func dryRunDiskSpaceSummary(required: Int64, available: Int64, passed: Bool) -> String {
        let status = passed ? "passed" : "failed"
        return "Required disk space check: \(status) (\(ByteSize(required)) required, \(ByteSize(available)) available)"
    }
}

// MARK: - Package selection/merge helpers
private extension ContentCoordinator {

    /// Determine whether a package needs to be downloaded and installed.
    ///
    /// 1. If `fileCheck` is empty → can't determine install state → needs install.
    /// 2. If no `fileCheck` path exists on disk → not installed → needs install.
    /// 3. If `fileCheck` paths exist but `pkg.version` is nil → can't version-compare
    ///    → treat as current (skip).
    /// 4. If `fileCheck` paths exist and `pkg.version` is set → run `pkgutil` to get
    ///    the local version:
    ///    - No receipt found (orphaned files) → needs install.
    ///    - Local version ≥ remote version → up to date → skip.
    ///    - Local version < remote version → update available → needs install.
    static func packageNeedsInstall(
        _ pkg: AudioContentPackage,
        debugLog: ((String) -> Void)?
    ) -> Bool {
        // 1. No fileCheck paths at all — can't tell, assume needs install.
        guard !pkg.fileCheck.isEmpty else {
            debugLog?("\(pkg.name): no fileCheck paths, assuming needs install")
            return true
        }

        // 2. No fileCheck path exists on disk — not installed.
        let anyPathExists = pkg.fileCheck.contains { FileManager.default.fileExists(atPath: $0) }
        guard anyPathExists else {
            debugLog?("\(pkg.name): not installed (no fileCheck paths found on disk)")
            return true
        }

        // 3. fileCheck paths exist but no remote version to compare — treat as current.
        guard let remoteVersion = pkg.version else {
            debugLog?("\(pkg.name): installed, no remote version to compare — treating as current")
            return false
        }

        // 4. fileCheck paths exist and remote version is known — check pkgutil receipt.
        do {
            guard let receipt = try PackageReceipt.loadIfInstalled(
                pkg.packageID,
                debugLog: debugLog
            ) else {
                // Orphaned files: fileCheck paths present but no receipt — reinstall.
                debugLog?("\(pkg.name): fileCheck paths exist but no pkgutil receipt — reinstalling")
                return true
            }

            guard let localVersion = receipt.version else {
                // Receipt exists but has no version — treat as needing install to be safe.
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
            // pkgutil unavailable or failed — fall back to fileCheck-only (treat as current).
            debugLog?("\(pkg.name): pkgutil error (\(error)) — treating as current")
            return false
        }
    }

    /// Merge packages across all target apps, deduplicating by package ID.
    ///
    /// `appPolicies` provides per-app `required`/`optional` overrides (used under `--managed`).
    /// Apps without a matching policy entry fall back to the global `includeRequired`/`includeOptional`.
    /// Pass an empty array (the default) to apply the global flags uniformly to all apps.
    static func mergePackagesAcrossApps(
        apps: [AudioApplication],
        includeRequired: Bool,
        includeOptional: Bool,
        appPolicies: [AppContentPolicy] = [],
        forceDeploy: Bool,
        debugLog: ((String) -> Void)?
    ) -> [AudioContentPackage] {

        // Build a lookup so per-app policy resolution is O(1).
        let policyByApp: [ConcreteApp: AppContentPolicy] = appPolicies.reduce(into: [:]) {
            $0[$1.app] = $1
        }

        var byID: [String: AudioContentPackage] = [:]
        var mandatoryIDs = Set<String>()

        for app in apps {
            // Resolve required/optional for this app: per-app policy takes precedence
            // over the global flags; falls back to global when no policy entry exists.
            let policy       = app.concreteApp.flatMap { policyByApp[$0] }
            let wantRequired = policy?.required ?? includeRequired
            let wantOptional = policy?.optional ?? includeOptional

            if wantRequired {
                for pkg in app.mandatory {
                    // Filter by install state per-app before merging, matching Python behaviour.
                    // This ensures shared packages with differing InstalledSize across app plists
                    // resolve consistently: whichever app's copy survives the install filter wins,
                    // with mandatory taking precedence over optional for the same packageID.
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

    static func effectiveBaseURL(cacheServer: URL?, mirrorServer: URL?) -> URL {
        mirrorServer
            ?? cacheServer
            ?? LoopdownConstants.Downloads.contentSourceBaseURL
    }

    static func packageRemoteURL(baseURL: URL, pkg: AudioContentPackage) -> URL {
        var url = baseURL
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

    /// Right-pad `n` to the same width as `total` so counters stay column-aligned.
    ///
    /// Example with total=46:  " 8 of 46",  " 9 of 46", "10 of 46"
    static func counter(_ n: Int, of total: Int) -> String {
        let width = String(total).count
        return String(format: "%\(width)d of %d", n, total)
    }
}
