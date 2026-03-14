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
    ///   - `destDir` is used for `download` mode output placement.
    ///   - `deploy` downloads into a managed staging directory and installs from there.
    ///   - `skipSignatureCheck`: when false (default), each downloaded package is verified
    ///     as signed Apple software before being saved/installed.
    public static func run(
        mode: Mode,
        selectedApps: [ConcreteApp],
        includeRequired: Bool,
        includeOptional: Bool,
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
        let pkgs = mergePackagesAcrossApps(
            apps: apps,
            includeRequired: includeRequired,
            includeOptional: includeOptional
        )

        if pkgs.isEmpty {
            logger.notice("No packages selected.")
            return
        }

        let total = pkgs.count

        if dryRun {
            for (idx, pkg) in pkgs.enumerated() {
                logger.info("\(counter(idx + 1, of: total)) - download: \(pkg.name) (\(pkg.downloadSize))")
            }
            logger.notice(dryRunDownloadSummary(for: pkgs))
            return
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
        forceDeploy: Bool,
        skipSignatureCheck: Bool,
        cacheServer: URL?,
        mirrorServer: URL?,
        dryRun: Bool,
        logger: CoreLogger,
        downloader: DownloadClient
    ) async throws {

        logger.debug("forceDeploy: \(forceDeploy)")
        if let cacheServer { logger.debug("cacheServer: \(cacheServer.absoluteString)") }
        if let mirrorServer { logger.debug("mirrorServer: \(mirrorServer.absoluteString)") }

        let baseURL = effectiveBaseURL(cacheServer: cacheServer, mirrorServer: mirrorServer)
        logger.notice("Downloading from \(baseURL.absoluteString) and installing content")

        // 1) Merge packages across all apps:
        //    - build a single list
        //    - mandatory wins over optional for same packageID
        let merged = mergePackagesAcrossApps(
            apps: apps,
            includeRequired: includeRequired,
            includeOptional: includeOptional
        )

        if merged.isEmpty {
            logger.notice("No packages selected for deploy.")
            return
        }

        // 2) Free space check (download + installed totals).
        // NOTE: This checks the filesystem backing URLSession temp directory.
        let totalDownload = merged.reduce(Int64(0)) { $0 + $1.downloadSize.raw }
        let totalInstalled = merged.reduce(Int64(0)) { $0 + $1.installedSize.raw }
        let requiredBytes = totalDownload + totalInstalled

        let checkPath = FileManager.default.temporaryDirectory.path
        let freeBytes = try filesystemFreeBytes(atPath: checkPath)

        logger.debug("Free bytes at '\(checkPath)': \(ByteSize(freeBytes))")

        if freeBytes < requiredBytes {
            throw ContentCoordinatorError.insufficientDiskSpace(
                required: requiredBytes,
                available: freeBytes,
                path: checkPath
            )
        }

        // 3) Dry-run: list packages then print download and install summaries.
        if dryRun {
            logger.notice("dry-run: no downloads or installs will occur.")
            logMergedPackagesForDeploy(merged, dryRun: true, forceDeploy: forceDeploy, logger: logger)
            logger.notice(dryRunDownloadSummary(for: merged))
            logger.notice(dryRunInstallSummary(for: merged))
            return
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

        // 5) Download into staging, verify signature, then install.
        logMergedPackagesForDeploy(merged, dryRun: false, forceDeploy: forceDeploy, logger: logger)

        var didInstallAny = false
        for (idx, pkg) in merged.enumerated() {
            let n = idx + 1
            let remoteURL = packageRemoteURL(baseURL: baseURL, pkg: pkg)

            // Skip packages whose content is already present on disk, unless --force is set.
            if !forceDeploy && packageIsInstalled(pkg) {
                logger.debug("already installed, skipping: \(pkg.name)")
                continue
            }

            logger.info("\(counter(n, of: merged.count)) - downloading: \(pkg.name)")

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
                    logger.error("\(counter(n, of: merged.count)) - signature check failed, skipping install: \(pkg.name)")
                    continue
                }
            }


            didInstallAny = true
            do {
                try PackageInstaller.install(
                    pkgURL: stagedURL,
                    packageName: pkg.name,
                    debugLog: logger.debug,
                    errorLog: logger.error
                )
                logger.notice("\(counter(n, of: merged.count)) - installed: \(pkg.name)")
            } catch {
                logger.error("\(counter(n, of: merged.count)) - failed to install: \(pkg.name) (\(error))")
            }
        }

        if !didInstallAny {
            logger.notice("All packages are already installed.")
        }
    }

    static func logMergedPackagesForDeploy(
        _ pkgs: [AudioContentPackage],
        dryRun: Bool,
        forceDeploy: Bool,
        logger: CoreLogger
    ) {
        let total = pkgs.count
        for (idx, pkg) in pkgs.enumerated() {
            let n = idx + 1
            if dryRun {
                if !forceDeploy && packageIsInstalled(pkg) {
                    logger.debug("would skip (already installed): \(pkg.name)")
                } else {
                    logger.info("\(counter(n, of: total)) - would download+install: \(pkg.name) (\(pkg.downloadSize) dl, \(pkg.installedSize) installed)")
                }
            }
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
            parts.append("\(required.count) required: \(ByteSize(reqSize).human)")
        }
        if !optional.isEmpty {
            parts.append("\(optional.count) optional: \(ByteSize(optSize).human)")
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

        let reqSize = required.reduce(Int64(0)) { $0 + $1.installedSize.raw }
        let optSize = optional.reduce(Int64(0)) { $0 + $1.installedSize.raw }
        let totalSize = reqSize + optSize

        var parts: [String] = []
        if !required.isEmpty {
            parts.append("\(required.count) required: \(ByteSize(reqSize).human)")
        }
        if !optional.isEmpty {
            parts.append("\(optional.count) optional: \(ByteSize(optSize).human)")
        }

        let breakdown = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "Total install size \(ByteSize(totalSize).human)\(breakdown)"
    }
}

// MARK: - Package selection/merge helpers
private extension ContentCoordinator {

    /// Determine if a package is already installed by checking whether any of its
    /// `fileCheck` paths exist on disk. Mirrors the Python implementation's approach.
    static func packageIsInstalled(_ pkg: AudioContentPackage) -> Bool {
        guard !pkg.fileCheck.isEmpty else { return false }
        return pkg.fileCheck.contains { FileManager.default.fileExists(atPath: $0) }
    }

    static func mergePackagesAcrossApps(
        apps: [AudioApplication],
        includeRequired: Bool,
        includeOptional: Bool
    ) -> [AudioContentPackage] {

        var byID: [String: AudioContentPackage] = [:]
        var mandatoryIDs = Set<String>()

        if includeRequired {
            for app in apps {
                for pkg in app.mandatory {
                    byID[pkg.packageID] = pkg
                    mandatoryIDs.insert(pkg.packageID)
                }
            }
        }

        if includeOptional {
            for app in apps {
                for pkg in app.optional {
                    if mandatoryIDs.contains(pkg.packageID) { continue }
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
