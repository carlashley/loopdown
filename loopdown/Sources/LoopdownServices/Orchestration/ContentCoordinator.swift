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

    public enum Mode: Sendable, CustomStringConvertible {
        case download
        case deploy

        public var description: String {
            switch self {
            case .download: return "download"
            case .deploy:   return "deploy"
            }
        }
    }

    /// Common entry point used by both `download` and `deploy` CLI commands.
    ///
    /// - Note:
    ///   - `selectedApps`: empty means "all installed apps that loopdown supports".
    ///   - `includeEssential` / `includeCore` / `includeOptional` are already validated by the CLI.
    ///   - `appPolicies`: per-app overrides under `--managed`. Empty means use the global flags.
    ///   - `libraryDestURL`: destination root for modern Logic Pro 12+ / MainStage 4+ content.
    ///   - `skipSignatureCheck`: applies to legacy `.pkg` only; modern `.aar` always skips.
    ///   - `cacheServer` and `mirrorServer` apply to both legacy and modern packages.
    ///   - `appGeneration`: restricts targeting to legacy-only or modern-only apps. `.any` targets both.
    public static func run(
        mode: Mode,
        selectedApps: [ConcreteApp],
        includeEssential: Bool,
        includeCore: Bool,
        includeOptional: Bool,
        appPolicies: [AppContentPolicy] = [],
        appGeneration: AppGeneration = .any,
        libraryDestURL: URL?,
        destDir: String,
        forceDeploy: Bool,
        skipSignatureCheck: Bool,
        cacheServer: URL?,
        mirrorServer: URL?,
        dryRun: Bool,
        maxRetries: Int = 3,
        retryDelay: Int = 2,
        minimumBandwidth: Int? = nil,
        bandwidthWindow: Int = 60,
        bandwidthAbortAfter: Int? = nil,
        verboseInstall: Bool = false,
        logger: CoreLogger
    ) async throws -> Bool {

        // Resolve library dest first to handle optional value
        let resolvedLibraryDestURL = libraryDestURL ?? URL(fileURLWithPath: LoopdownConstants.ModernApps.defaultLibraryDestPath, isDirectory: true)

        // 1) Resolve installed apps and filter by CLI selection (if any).
        let installed = Array(
            InstalledApplicationResolver.resolveInstalled(
                libraryDestURL: resolvedLibraryDestURL,
                logger: logger
            )
        )

        let targetApps: [AudioApplication] = {
            var apps: [AudioApplication] = installed

            if !selectedApps.isEmpty {
                apps = apps.filter { app in
                    guard let c = app.concreteApp else { return false }
                    return selectedApps.contains(c)
                }
            }

            switch appGeneration {
            case .any:
                break
            case .legacyOnly:
                apps = apps.filter { !$0.isModernised }
            case .modernOnly:
                apps = apps.filter { $0.isModernised }
            }

            return apps
        }()

        if targetApps.isEmpty {
            logger.notice("No supported installed applications found (or none matched the requested selection).")
            return false
        }

        let downloader = DownloadClient(maxRedirects: 5)

        switch mode {
        case .download:
            return try await runDownload(
                apps: targetApps,
                includeEssential: includeEssential,
                includeCore: includeCore,
                includeOptional: includeOptional,
                mode: mode,
                destDir: destDir,
                skipSignatureCheck: skipSignatureCheck,
                cacheServer: cacheServer,
                mirrorServer: mirrorServer,
                dryRun: dryRun,
                maxRetries: maxRetries,
                retryDelay: retryDelay,
                minimumBandwidth: minimumBandwidth,
                bandwidthWindow: bandwidthWindow,
                bandwidthAbortAfter: bandwidthAbortAfter,
                logger: logger,
                downloader: downloader
            )

        case .deploy:
            return try await runDeploy(
                apps: targetApps,
                includeEssential: includeEssential,
                includeCore: includeCore,
                includeOptional: includeOptional,
                appPolicies: appPolicies,
                libraryDestURL: resolvedLibraryDestURL,
                mode: mode,
                forceDeploy: forceDeploy,
                skipSignatureCheck: skipSignatureCheck,
                cacheServer: cacheServer,
                mirrorServer: mirrorServer,
                dryRun: dryRun,
                maxRetries: maxRetries,
                retryDelay: retryDelay,
                minimumBandwidth: minimumBandwidth,
                bandwidthWindow: bandwidthWindow,
                bandwidthAbortAfter: bandwidthAbortAfter,
                verboseInstall: verboseInstall,
                logger: logger,
                downloader: downloader
            )
        }
    }
}

// MARK: - Download mode
private extension ContentCoordinator {

    @discardableResult
    static func runDownload(
        apps: [AudioApplication],
        includeEssential: Bool,
        includeCore: Bool,
        includeOptional: Bool,
        mode: Mode,
        destDir: String,
        skipSignatureCheck: Bool,
        cacheServer: URL?,
        mirrorServer: URL?,
        dryRun: Bool,
        maxRetries: Int,
        retryDelay: Int,
        minimumBandwidth: Int?,
        bandwidthWindow: Int,
        bandwidthAbortAfter: Int?,
        logger: CoreLogger,
        downloader: DownloadClient
    ) async throws -> Bool {

        let baseURL = effectiveBaseURL(cacheServer: cacheServer, mirrorServer: mirrorServer)
        logger.notice("Downloading from \(baseURL.absoluteString) and saving content to \(destDir)")

        let pkgs = mergePackagesAcrossApps(
            apps: apps,
            includeEssential: includeEssential,
            includeCore: includeCore,
            includeOptional: includeOptional,
            forceDeploy: false,
            debugLog: nil
        )

        if pkgs.isEmpty {
            logger.notice("No packages selected for \(mode).")
            return false
        }

        let requiredBytes = pkgs.reduce(Int64(0)) { $0 + $1.downloadSize.raw }
        let checkPath = FileManager.default.temporaryDirectory.path
        let freeBytes = try filesystemFreeBytes(atPath: checkPath)

        logger.debug("Free bytes at '\(checkPath)': \(ByteSize(freeBytes))")

        let total = pkgs.count

        if dryRun {
            for (idx, pkg) in pkgs.enumerated() {
                let n         = counter(idx + 1, of: total)
                let remoteURL = packageRemoteURL(pkg: pkg, cacheServer: cacheServer, mirrorServer: mirrorServer)
                logger.info("\(n) - download: \(pkg.name) (\(pkg.downloadSize))")
                logger.debug("\(n) - url: \(remoteURL.absoluteString)")
            }
            logger.notice(dryRunDownloadSummary(for: pkgs))
            let passed = freeBytes >= requiredBytes
            logger.notice(dryRunDiskSpaceSummary(required: requiredBytes, available: freeBytes, passed: passed))
            return true
        }

        if freeBytes < requiredBytes {
            throw ContentCoordinatorError.insufficientDiskSpace(
                required: requiredBytes,
                available: freeBytes,
                path: checkPath
            )
        }

        // Helper: attempt a single package download. Returns true on success.
        enum DownloadPackageResult { case success; case bandwidthFailure; case otherFailure }
        func attemptDownloadPackage(_ pkg: AudioContentPackage, label: String) async -> DownloadPackageResult {
            let remoteURL = packageRemoteURL(pkg: pkg, cacheServer: cacheServer, mirrorServer: mirrorServer)
            let destURL   = destinationFileURL(destDir: destDir, pkg: pkg)

            logger.info("\(label) - downloading: \(pkg.name) (\(pkg.downloadSize))")
            logger.fileOnly("\(label) - url: \(remoteURL.absoluteString)")

            do {
                let tempURL = try await downloader.downloadTempFile(
                    from: remoteURL,
                    maxRetries: maxRetries,
                    retryDelay: TimeInterval(retryDelay),
                    minimumBandwidth: minimumBandwidth,
                    bandwidthWindow: bandwidthWindow,
                    onRetry: { attempt, max, error in
                        logger.warning("\(label) - retry \(attempt)/\(max): \(pkg.name) (\(error.localizedDescription))")
                    }
                )

                if pkg.isLegacy && !skipSignatureCheck {
                    guard PackageSignatureChecker.isSignedAppleSoftware(
                        pkgURL: tempURL,
                        debugLog: logger.debug
                    ) else {
                        try? FileManager.default.removeItem(at: tempURL)
                        logger.error("\(label) - signature check failed, discarding: \(pkg.name)")
                        return .otherFailure
                    }
                }

                try moveReplacingIfExists(from: tempURL, to: destURL)
                logger.info("\(label) - saved: \(pkg.name)")
                return .success
            } catch let error as DownloadClientError {
                logger.error("\(label) - failed: \(pkg.name) (\(error.localizedDescription))")
                if case .belowMinimumBandwidth = error { return .bandwidthFailure }
                return .otherFailure
            } catch {
                logger.error("\(label) - failed: \(pkg.name) (\(error.localizedDescription))")
                return .otherFailure
            }
        }

        // Main pass.
        var failedPkgs: [AudioContentPackage] = []
        var consecutiveBandwidthFailures = 0
        for (idx, pkg) in pkgs.enumerated() {
            let result = await attemptDownloadPackage(pkg, label: counter(idx + 1, of: total))
            switch result {
            case .success:
                consecutiveBandwidthFailures = 0
            case .bandwidthFailure:
                failedPkgs.append(pkg)
                consecutiveBandwidthFailures += 1
                if let limit = bandwidthAbortAfter, consecutiveBandwidthFailures >= limit {
                    throw ContentCoordinatorError.bandwidthAbortThresholdReached(consecutive: consecutiveBandwidthFailures)
                }
            case .otherFailure:
                consecutiveBandwidthFailures = 0
                failedPkgs.append(pkg)
            }
        }

        // Single retry pass for any failures.
        if !failedPkgs.isEmpty {
            logger.notice("Retrying \(failedPkgs.count) failed package(s)...")
            var stillFailed: [AudioContentPackage] = []
            for (idx, pkg) in failedPkgs.enumerated() {
                let label = "retry \(counter(idx + 1, of: failedPkgs.count))"
                let result = await attemptDownloadPackage(pkg, label: label)
                if case .success = result { } else { stillFailed.append(pkg) }
            }
            if !stillFailed.isEmpty {
                logger.warning("\(stillFailed.count) package(s) failed after retry: \(stillFailed.map { $0.name }.joined(separator: ", "))")
            }
        }

        return true
    }
}

// MARK: - Deploy mode
private extension ContentCoordinator {

    static func runDeploy(
        apps: [AudioApplication],
        includeEssential: Bool,
        includeCore: Bool,
        includeOptional: Bool,
        appPolicies: [AppContentPolicy],
        libraryDestURL: URL?, // nil only in download mode; guarded inside attemptDeployPackage for modern packages
        mode: Mode,
        forceDeploy: Bool,
        skipSignatureCheck: Bool,
        cacheServer: URL?,
        mirrorServer: URL?,
        dryRun: Bool,
        maxRetries: Int,
        retryDelay: Int,
        minimumBandwidth: Int?,
        bandwidthWindow: Int,
        bandwidthAbortAfter: Int?,
        verboseInstall: Bool,
        logger: CoreLogger,
        downloader: DownloadClient
    ) async throws -> Bool {

        logger.debug("forceDeploy: \(forceDeploy)")
        logger.debug("libraryDestURL: \(libraryDestURL?.path ?? "none")")
        if let cacheServer  { logger.debug("cacheServer: \(cacheServer.absoluteString)") }
        if let mirrorServer { logger.debug("mirrorServer: \(mirrorServer.absoluteString)") }

        let baseURL = effectiveBaseURL(cacheServer: cacheServer, mirrorServer: mirrorServer)
        logger.notice("Downloading from \(baseURL.absoluteString) and installing content")

        let pending = mergePackagesAcrossApps(
            apps: apps,
            includeEssential: includeEssential,
            includeCore: includeCore,
            includeOptional: includeOptional,
            appPolicies: appPolicies,
            forceDeploy: forceDeploy,
            debugLog: logger.debug
        )

        if pending.isEmpty {
            logger.notice("No packages selected for \(mode).")
            return false
        }

        // Build the deploy record: attribute each pending package back to its source app.
        // A package may appear in multiple apps' metadata; we assign it to the first app
        // whose bucket contains it, consistent with mergePackagesAcrossApps priority.
        let pendingIDs  = Set(pending.map { $0.packageID })
        let runDate    = Date()
        let runDateStr = DeployRunRecord.utcFormatter.string(from: runDate)

        // Per-app checked sets, keyed by (generation, appKey).
        // Built now; installed entries are appended after the install loop.
        var pendingRecords: [(generation: String, appKey: String, record: DeployRunRecord.AppRecord)] = []

        for app in apps {
            guard let key = app.concreteApp?.rawValue else { continue }
            let generation = app.isModernised ? "modern" : "legacy"
            var appRecord  = DeployRunRecord.AppRecord(runDate: runDateStr, appVersion: app.version)

            for pkg in app.essential where pendingIDs.contains(pkg.packageID) {
                appRecord.essential.checked.append(pkg.packageID)
            }
            for pkg in app.core where pendingIDs.contains(pkg.packageID) {
                appRecord.core.checked.append(pkg.packageID)
            }
            for pkg in app.optional where pendingIDs.contains(pkg.packageID) {
                appRecord.optional.checked.append(pkg.packageID)
            }

            if !appRecord.essential.checked.isEmpty || !appRecord.core.checked.isEmpty || !appRecord.optional.checked.isEmpty {
                pendingRecords.append((generation: generation, appKey: key, record: appRecord))
            }
        }

        let totalDownload  = pending.reduce(Int64(0)) { $0 + $1.downloadSize.raw }
        let totalInstalled = pending.reduce(Int64(0)) { $0 + $1.installedSize.raw }
        let requiredBytes  = totalDownload + totalInstalled

        let checkPath = FileManager.default.temporaryDirectory.path
        let freeBytes = try filesystemFreeBytes(atPath: checkPath)

        logger.debug("Free bytes at '\(checkPath)': \(ByteSize(freeBytes))")

        if dryRun {
            listPackagesForDryRunDeploy(
                pending,
                cacheServer: cacheServer,
                mirrorServer: mirrorServer,
                logger: logger
            )
            logger.notice(dryRunDownloadSummary(for: pending))
            logger.notice(dryRunInstallSummary(for: pending))
            let passed = freeBytes >= requiredBytes
            logger.notice(dryRunDiskSpaceSummary(required: requiredBytes, available: freeBytes, passed: passed))
            return pending.contains(where: { !$0.isLegacy })
        }

        if freeBytes < requiredBytes {
            throw ContentCoordinatorError.insufficientDiskSpace(
                required: requiredBytes,
                available: freeBytes,
                path: checkPath
            )
        }

        let staging = try TemporaryDirectory()
        let signalCleanup = SignalCleanup { staging.cleanup() }
        signalCleanup.install()

        defer {
            signalCleanup.uninstall()
            staging.cleanup()
        }

        // Result returned from the per-package helper.
        enum DeployPackageResult {
            case success(packageID: String, installedDate: String, deployedModern: Bool)
            case bandwidthFailure
            case failure
        }

        // Helper: attempt download + install for a single package.
        func attemptDeployPackage(_ pkg: AudioContentPackage, label: String) async -> DeployPackageResult {
            let remoteURL = packageRemoteURL(pkg: pkg, cacheServer: cacheServer, mirrorServer: mirrorServer)

            logger.info("\(label) - downloading: \(pkg.name)")
            logger.fileOnly("\(label) - url: \(remoteURL.absoluteString)")

            let stagedURL: URL
            do {
                let tempURL = try await downloader.downloadTempFile(
                    from: remoteURL,
                    maxRetries: maxRetries,
                    retryDelay: TimeInterval(retryDelay),
                    minimumBandwidth: minimumBandwidth,
                    bandwidthWindow: bandwidthWindow,
                    onRetry: { attempt, max, error in
                        logger.warning("\(label) - retry \(attempt)/\(max): \(pkg.name) (\(error.localizedDescription))")
                    }
                )
                let dest = staging.url.appendingPathComponent(pkg.name)
                try FileManager.default.moveItem(at: tempURL, to: dest)
                stagedURL = dest
            } catch let error as DownloadClientError {
                logger.error("\(label) - failed to download: \(pkg.name) (\(error.localizedDescription))")
                if case .belowMinimumBandwidth = error { return .bandwidthFailure }
                return .failure
            } catch {
                logger.error("\(label) - failed to download: \(pkg.name) (\(error.localizedDescription))")
                return .failure
            }

            if pkg.isLegacy && !skipSignatureCheck {
                guard PackageSignatureChecker.isSignedAppleSoftware(
                    pkgURL: stagedURL,
                    debugLog: logger.debug
                ) else {
                    logger.error("\(label) - signature check failed, skipping install: \(pkg.name)")
                    return .failure
                }
            }

            let indent = String(repeating: " ", count: label.count + 3)

            if pkg.isLegacy {
                do {
                    try PackageInstaller.install(
                        pkgURL: stagedURL,
                        packageName: pkg.name,
                        verbose: verboseInstall,
                        debugLog: logger.debug,
                        errorLog: logger.error
                    )
                    logger.notice("\(indent)installed: \(pkg.name)")
                    return .success(
                        packageID: pkg.packageID,
                        installedDate: DeployRunRecord.utcFormatter.string(from: Date()),
                        deployedModern: false
                    )
                } catch {
                    logger.error("\(indent)failed to install: \(pkg.name) (\(error))")
                    return .failure
                }
            } else {
                do {
                    // guard against empty libraryDestURL
                    guard let libraryDestURL else {
                        logger.error("\(indent)libraryDestURL is nil for modern package — this is a bug")
                        return .failure
                    }
                    try AARExtractor.extract(
                        packageURL: stagedURL,
                        packageName: pkg.name,
                        libraryDestURL: libraryDestURL,
                        debugLog: logger.debug,
                        errorLog: logger.error
                    )
                    logger.notice("\(indent)extracted: \(pkg.name)")
                    return .success(
                        packageID: pkg.packageID,
                        installedDate: DeployRunRecord.utcFormatter.string(from: Date()),
                        deployedModern: true
                    )
                } catch {
                    logger.error("\(indent)failed to extract: \(pkg.name) (\(error))")
                    return .failure
                }
            }
        }

        func applyResult(_ result: DeployPackageResult) {
            if case .success(let packageID, let installedDate, let deployedModern) = result {
                installedTimestamps[packageID] = installedDate
                if deployedModern { modernContentDeployed = true }
            }
        }

        // Xcode will randomly spuriously indicate these two vars are never mutated; this is wrong, they are mutated elsewhere but Xcode doesn't
        // see this
        // swiftlint:disable:next prefer_let
        var modernContentDeployed = false
        // Maps packageID -> UTC install timestamp.
        // swiftlint:disable:next prefer_let
        var installedTimestamps: [String: String] = [:]

        // Main pass.
        let total = pending.count
        var failedPkgs: [AudioContentPackage] = []
        var consecutiveBandwidthFailures = 0
        for (idx, pkg) in pending.enumerated() {
            let result = await attemptDeployPackage(pkg, label: counter(idx + 1, of: total))
            switch result {
            case .success:
                consecutiveBandwidthFailures = 0
                applyResult(result)
            case .bandwidthFailure:
                failedPkgs.append(pkg)
                consecutiveBandwidthFailures += 1
                if let limit = bandwidthAbortAfter, consecutiveBandwidthFailures >= limit {
                    throw ContentCoordinatorError.bandwidthAbortThresholdReached(consecutive: consecutiveBandwidthFailures)
                }
            case .failure:
                consecutiveBandwidthFailures = 0
                failedPkgs.append(pkg)
            }
        }

        // Single retry pass for any failures.
        if !failedPkgs.isEmpty {
            logger.notice("Retrying \(failedPkgs.count) failed package(s)...")
            var stillFailed: [AudioContentPackage] = []
            for (idx, pkg) in failedPkgs.enumerated() {
                let label = "retry \(counter(idx + 1, of: failedPkgs.count))"
                let result = await attemptDeployPackage(pkg, label: label)
                if case .failure = result {
                    stillFailed.append(pkg)
                } else {
                    applyResult(result)
                }
            }
            if !stillFailed.isEmpty {
                logger.warning("\(stillFailed.count) package(s) failed after retry: \(stillFailed.map { $0.name }.joined(separator: ", "))")
            }
        }

        // Populate installed entries and collect only apps that had at least one install.
        var updatedRecords: [(generation: String, appKey: String, record: DeployRunRecord.AppRecord)] = []

        for (generation, appKey, var appRecord) in pendingRecords {
            let makeInstalled: (String) -> DeployRunRecord.InstalledPackage? = { id in
                guard let ts = installedTimestamps[id] else { return nil }
                return DeployRunRecord.InstalledPackage(id: id, installedDate: ts)
            }
            appRecord.essential.installed = appRecord.essential.checked.compactMap { makeInstalled($0) }
            appRecord.core.installed      = appRecord.core.checked.compactMap      { makeInstalled($0) }
            appRecord.optional.installed  = appRecord.optional.checked.compactMap  { makeInstalled($0) }

            let anyInstalled = !appRecord.essential.installed.isEmpty
                || !appRecord.core.installed.isEmpty
                || !appRecord.optional.installed.isEmpty
            if anyInstalled {
                updatedRecords.append((generation: generation, appKey: appKey, record: appRecord))
            }
        }

        if !updatedRecords.isEmpty {
            do {
                try DeployRunRecord.mergeAndWrite(updatedApps: updatedRecords, runDate: runDate)
            } catch {
                logger.error("Failed to write deploy run record: \(error)")
            }
        }

        return modernContentDeployed
    }

    static func listPackagesForDryRunDeploy(
        _ pkgs: [AudioContentPackage],
        cacheServer: URL?,
        mirrorServer: URL?,
        logger: CoreLogger
    ) {
        let total = pkgs.count
        for (idx, pkg) in pkgs.enumerated() {
            let n         = counter(idx + 1, of: total)
            let remoteURL = packageRemoteURL(pkg: pkg, cacheServer: cacheServer, mirrorServer: mirrorServer)
            logger.info("\(n) - download+install: \(pkg.name) (\(pkg.downloadSize) dl, \(pkg.installedSize) installed)")
            logger.debug("\(n) - url: \(remoteURL.absoluteString)")
        }
    }
}

// MARK: - Dry-run summary helpers
private extension ContentCoordinator {

    static func dryRunDownloadSummary(for pkgs: [AudioContentPackage]) -> String {
        let essential = pkgs.filter { $0.isEssential }
        let core      = pkgs.filter { $0.isCore }
        let optional  = pkgs.filter { $0.isOptional }

        let esnSize  = essential.reduce(Int64(0)) { $0 + $1.downloadSize.raw }
        let coreSize = core.reduce(Int64(0))      { $0 + $1.downloadSize.raw }
        let optSize  = optional.reduce(Int64(0))  { $0 + $1.downloadSize.raw }

        var parts: [String] = []
        if !essential.isEmpty { parts.append("\(essential.count) essential: \(ByteSize(esnSize))") }
        if !core.isEmpty      { parts.append("\(core.count) core: \(ByteSize(coreSize))") }
        if !optional.isEmpty  { parts.append("\(optional.count) optional: \(ByteSize(optSize))") }

        let breakdown = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "Total download \(pkgs.count) package\(pkgs.count == 1 ? "" : "s")\(breakdown)"
    }

    static func dryRunInstallSummary(for pkgs: [AudioContentPackage]) -> String {
        let essential = pkgs.filter { $0.isEssential }
        let core      = pkgs.filter { $0.isCore }
        let optional  = pkgs.filter { $0.isOptional }

        let esnSize  = essential.reduce(Int64(0)) { $0 + $1.installedSize.raw }
        let coreSize = core.reduce(Int64(0))      { $0 + $1.installedSize.raw }
        let optSize  = optional.reduce(Int64(0))  { $0 + $1.installedSize.raw }
        let total    = esnSize + coreSize + optSize

        var parts: [String] = []
        if !essential.isEmpty { parts.append("\(essential.count) essential: \(ByteSize(esnSize))") }
        if !core.isEmpty      { parts.append("\(core.count) core: \(ByteSize(coreSize))") }
        if !optional.isEmpty  { parts.append("\(optional.count) optional: \(ByteSize(optSize))") }

        let breakdown = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "Total install size \(ByteSize(total))\(breakdown)"
    }

    static func dryRunDiskSpaceSummary(required: Int64, available: Int64, passed: Bool) -> String {
        let status = passed ? "passed" : "failed"
        return "Required disk space check: \(status) (\(ByteSize(required)) required, \(ByteSize(available)) available)"
    }
}

// MARK: - Package selection/merge helpers
private extension ContentCoordinator {

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
        guard !pkg.fileCheck.isEmpty else {
            debugLog?("\(pkg.name): no receipt/fileCheck paths — treating as not installed")
            return true
        }
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
    ///
    /// Priority when the same package ID appears in multiple apps:
    /// non-optional (essential or core) always wins over optional, matching
    /// Python's `prefer_essential_or_core_pkg` / `not pkg.is_optional` logic.
    static func mergePackagesAcrossApps(
        apps: [AudioApplication],
        includeEssential: Bool,
        includeCore: Bool,
        includeOptional: Bool,
        appPolicies: [AppContentPolicy] = [],
        forceDeploy: Bool,
        debugLog: ((String) -> Void)?
    ) -> [AudioContentPackage] {

        let policyByApp: [ConcreteApp: AppContentPolicy] = appPolicies.reduce(into: [:]) {
            $0[$1.app] = $1
        }

        var byID: [String: AudioContentPackage] = [:]
        // Track IDs that are essential or core so optional duplicates are skipped.
        var nonOptionalIDs = Set<String>()

        for app in apps {
            let policy       = app.concreteApp.flatMap { policyByApp[$0] }
            let wantEssential = policy?.essential ?? includeEssential
            let wantCore      = policy?.core      ?? includeCore
            let wantOptional  = policy?.optional  ?? includeOptional

            // Essential packages
            if wantEssential {
                for pkg in app.essential {
                    if !forceDeploy && !packageNeedsInstall(pkg, debugLog: debugLog) { continue }
                    if byID[pkg.packageID].map({ $0.isOptional }) ?? true {
                        byID[pkg.packageID] = pkg
                    }
                    nonOptionalIDs.insert(pkg.packageID)
                }
            }

            // Core packages
            if wantCore {
                for pkg in app.core {
                    if !forceDeploy && !packageNeedsInstall(pkg, debugLog: debugLog) { continue }
                    if byID[pkg.packageID].map({ $0.isOptional }) ?? true {
                        byID[pkg.packageID] = pkg
                    }
                    nonOptionalIDs.insert(pkg.packageID)
                }
            }

            // Optional packages — skip if already claimed by essential or core
            if wantOptional {
                for pkg in app.optional {
                    if nonOptionalIDs.contains(pkg.packageID) { continue }
                    if !forceDeploy && !packageNeedsInstall(pkg, debugLog: debugLog) { continue }
                    if byID[pkg.packageID] == nil {
                        byID[pkg.packageID] = pkg
                    }
                }
            }
        }

        // Sort: essential first, then core, then optional; within each bucket by name.
        return byID.values.sorted {
            if $0.isEssential != $1.isEssential { return $0.isEssential }
            if $0.isCore != $1.isCore           { return $0.isCore }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
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
    case bandwidthAbortThresholdReached(consecutive: Int)

    public var description: String {
        switch self {
        case .insufficientDiskSpace(let required, let available, let path):
            return "Insufficient disk space at '\(path)'. Required=\(ByteSize(required)), Available=\(ByteSize(available))"
        case .unableToReadDiskSpace(let path):
            return "Unable to read disk space information for '\(path)'."
        case .bandwidthAbortThresholdReached(let consecutive):
            return "Run aborted: \(consecutive) consecutive package(s) failed due to bandwidth threshold."
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
    /// (`universal/ContentPacks_3/…`) content is baked into each package's `downloadPath`,
    /// so the server base is always applied uniformly.
    static func effectiveBaseURL(cacheServer: URL?, mirrorServer: URL?) -> URL {
        mirrorServer
            ?? cacheServer
            ?? LoopdownConstants.Downloads.contentSourceBaseURL
    }

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
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        try ensureParentDirectoryExists(for: dst)
        try fm.moveItem(at: src, to: dst)
    }

    static func counter(_ n: Int, of total: Int) -> String {
        let width = String(total).count
        return String(format: "%\(width)d of %d", n, total)
    }
}
