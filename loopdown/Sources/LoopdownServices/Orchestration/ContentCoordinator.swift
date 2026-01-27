//// ContentCoordinator.swift
// loopdown
//
// Created on 27/1/2026
//
    

import Foundation
import LoopdownCore


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
    ///   - `destDir` is used for `download` mode output placement. `deploy` uses a staging dir when not dry-run.
    public static func run(
        mode: Mode,
        selectedApps: [ConcreteApp],
        includeRequired: Bool,
        includeOptional: Bool,
        destDir: String,
        forceDeploy: Bool,
        cacheServer: URL?,
        mirrorServer: URL?,
        dryRun: Bool,
        logger: CoreLogger
    ) throws {

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

        // 2) Select packages based on mode.
        switch mode {
        case .download:
            try runDownload(
                apps: targetApps,
                includeRequired: includeRequired,
                includeOptional: includeOptional,
                destDir: destDir,
                dryRun: dryRun,
                logger: logger
            )

        case .deploy:
            try runDeploy(
                apps: targetApps,
                includeRequired: includeRequired,
                includeOptional: includeOptional,
                destDir: destDir,
                forceDeploy: forceDeploy,
                cacheServer: cacheServer,
                mirrorServer: mirrorServer,
                dryRun: dryRun,
                logger: logger
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
        dryRun: Bool,
        logger: CoreLogger
    ) throws {

        logger.info("Mode: download")
        logger.info("Destination: \(destDir)")

        for app in apps {
            logger.info("=== \(app.name) \(app.version) ===")

            let pkgs = packagesForSingleApp(
                app,
                includeRequired: includeRequired,
                includeOptional: includeOptional
            )

            if pkgs.isEmpty {
                logger.notice("No packages selected for \(app.name).")
                continue
            }

            let total = pkgs.count
            for (idx, pkg) in pkgs.enumerated() {
                let n = idx + 1
                if dryRun {
                    logger.info("[\(n)/\(total)] would download: \(pkg.name) (\(pkg.downloadSize))")
                } else {
                    logger.info("[\(n)/\(total)] downloading: \(pkg.name) (\(pkg.downloadSize))")
                    // TODO: shared URLSession downloader goes here
                    // try downloader.download(pkg: pkg, to: destDir, logger: logger)
                }
            }
        }
    }
}

// MARK: - Deploy mode
private extension ContentCoordinator {

    static func runDeploy(
        apps: [AudioApplication],
        includeRequired: Bool,
        includeOptional: Bool,
        destDir: String,
        forceDeploy: Bool,
        cacheServer: URL?,
        mirrorServer: URL?,
        dryRun: Bool,
        logger: CoreLogger
    ) throws {

        logger.info("Mode: deploy")
        logger.info("forceDeploy: \(forceDeploy)")
        if let cacheServer { logger.info("cacheServer: \(cacheServer)") }
        if let mirrorServer { logger.info("mirrorServer: \(mirrorServer.absoluteString)") }

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
        // NOTE: this checks the filesystem of the staging location. If install location differs,
        // you may later split this into two checks.
        let totalDownload = merged.reduce(Int64(0)) { $0 + $1.downloadSize.raw }
        let totalInstalled = merged.reduce(Int64(0)) { $0 + $1.installedSize.raw }
        let requiredBytes = totalDownload + totalInstalled

        // For deploy: staging dir only when not dry-run; otherwise just check the declared dest.
        let checkPath = dryRun ? destDir : FileManager.default.temporaryDirectory.path
        let freeBytes = try filesystemFreeBytes(atPath: checkPath)

        logger.info("Total download: \(ByteSize(totalDownload))")
        logger.info("Total installed: \(ByteSize(totalInstalled))")
        logger.info("Total required: \(ByteSize(requiredBytes))")
        logger.info("Free bytes at '\(checkPath)': \(ByteSize(freeBytes))")

        if freeBytes < requiredBytes {
            throw ContentCoordinatorError.insufficientDiskSpace(
                required: requiredBytes,
                available: freeBytes,
                path: checkPath
            )
        }

        // 3) Deploy staging directory lifecycle
        if dryRun {
            logger.notice("dry-run: no staging directory will be created.")
            logMergedPackagesForDeploy(merged, dryRun: true, logger: logger)
            return
        }

        let staging = try TemporaryDirectory(prefix: "loopdown-staging-")
        logger.info("staging: \(staging.url.path)")

        let signalCleanup = SignalCleanup { staging.cleanup() }
        signalCleanup.install()

        defer {
            // If you add uninstall() later, call it here.
            staging.cleanup()
        }

        // 4) Download then install
        logMergedPackagesForDeploy(merged, dryRun: false, logger: logger)

        for (idx, pkg) in merged.enumerated() {
            let n = idx + 1
            logger.info("[\(n)/\(merged.count)] downloading: \(pkg.name)")
            // TODO: shared URLSession downloader goes here (download into staging.url)
            // try downloader.download(pkg: pkg, to: staging.url, logger: logger)

            // TODO: install goes here (placeholder only, per your request)
            // try installer.install(pkgAt: downloadedURL, logger: logger)
        }

        // If you want to keep staging for debugging in the future:
        // staging.keep()
    }

    static func logMergedPackagesForDeploy(
        _ pkgs: [AudioContentPackage],
        dryRun: Bool,
        logger: CoreLogger
    ) {
        let total = pkgs.count
        for (idx, pkg) in pkgs.enumerated() {
            let n = idx + 1
            if dryRun {
                logger.info("[\(n)/\(total)] would download+install: \(pkg.name) (\(pkg.downloadSize) dl, \(pkg.installedSize) installed)")
            } else {
                logger.info("[\(n)/\(total)] will download+install: \(pkg.name) (\(pkg.downloadSize) dl, \(pkg.installedSize) installed)")
            }
        }
    }
}

// MARK: - Package selection/merge helpers
private extension ContentCoordinator {

    static func packagesForSingleApp(
        _ app: AudioApplication,
        includeRequired: Bool,
        includeOptional: Bool
    ) -> [AudioContentPackage] {
        var out: [AudioContentPackage] = []

        if includeRequired { out.append(contentsOf: app.mandatory) }
        if includeOptional { out.append(contentsOf: app.optional) }

        // Stable ordering for display.
        out.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return out
    }

    static func mergePackagesAcrossApps(
        apps: [AudioApplication],
        includeRequired: Bool,
        includeOptional: Bool
    ) -> [AudioContentPackage] {

        // Key by packageID (your identity field).
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
                    // If mandatory already present, it strictly wins.
                    if mandatoryIDs.contains(pkg.packageID) { continue }
                    if byID[pkg.packageID] == nil {
                        byID[pkg.packageID] = pkg
                    }
                }
            }
        }

        // Return deterministic order.
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
