//// IncrementalDBFetcher.swift
// loopdown
//
// Created on 23/5/2026
//

import Foundation
import LoopdownCore


// MARK: - IncrementalDBFetcher

/// Downloads and unpacks incremental content DB archives for modern Logic Pro / MainStage.
///
/// For each pending version integer `v`, this type:
///   1. Builds the download URL: `<baseURL>/universal/contentDB_v<v>.aar`
///      (e.g. `https://audiocontentdownload.apple.com/universal/contentDB_v18.aar`).
///   2. Downloads the `.aar` to a temporary file.
///   3. Extracts the archive using `/usr/bin/aa extract -d <tempDir>`.
///   4. Locates the `contentDB_vXXXX.bundle` directory inside `<tempDir>`.
///   5. Parses `Package.plist` inside that bundle via `IncrementalContentDatabase`.
///
/// Results from all versions are merged, deduplicating by `packageID`. The caller
/// (typically `ContentCoordinator`) is responsible for deduplicating against packages
/// already present in the shipped SQLite content database.
///
/// This is performed once per `loopdown` invocation. Logic Pro and MainStage share the
/// same incremental content DB stream, so a single fetch covers both apps.
///
/// Mirrors Python `IncrementalDBFetcher` in `services/incremental_db_fetcher.py`.
public enum IncrementalDBFetcher {

    // MARK: - Constants

    private enum Consts {
        static let archiveRelPathPrefix = LoopdownConstants.Downloads.IncrementalContentDB.archiveRelativePathPrefix
        static let archiveSuffix        = LoopdownConstants.Downloads.IncrementalContentDB.archiveSuffix
        static let bundleDirPrefix      = LoopdownConstants.Downloads.IncrementalContentDB.extractedBundlePrefix
        static let bundleDirSuffix      = LoopdownConstants.Downloads.IncrementalContentDB.extractedBundleSuffix
        static let aaPath               = "/usr/bin/aa"
    }


    // MARK: - Public API

    /// Fetch and decode incremental content packages for the given version numbers.
    ///
    /// - Parameters:
    ///   - versions:        Version integers to fetch (e.g. `[16, 17, 18]`), ascending.
    ///   - libraryDestURL:  Root of the Logic Pro Library bundle; used for receipt lookup.
    ///   - cacheServer:     Optional caching/proxy server (used in place of Apple CDN).
    ///   - mirrorServer:    Optional mirror server (highest priority).
    ///   - downloader:      Shared `DownloadClient` instance.
    ///   - logger:          Logger for debug and error output.
    /// - Returns: Deduplicated array of `AudioContentPackage` values (non-legacy, modern),
    ///            merged across all versions in ascending order. Later versions win on conflict.
    public static func fetch(
        versions: [Int],
        libraryDestURL: URL,
        cacheServer: URL?,
        mirrorServer: URL?,
        downloader: DownloadClient,
        logger: CoreLogger = NullLogger()
    ) async -> [AudioContentPackage] {
        guard !versions.isEmpty else { return [] }

        guard FileManager.default.isExecutableFile(atPath: Consts.aaPath) else {
            logger.error("IncrementalDBFetcher: '\(Consts.aaPath)' not found — cannot fetch incremental content DB")
            return []
        }

        let baseURL = effectiveBaseURL(cacheServer: cacheServer, mirrorServer: mirrorServer)

        // Merged results: later versions overwrite earlier ones on ID conflict.
        var byID: [String: AudioContentPackage] = [:]

        for version in versions {
            logger.debug("IncrementalDBFetcher: processing v\(version)")

            guard let pkgs = await fetchOneVersion(
                version: version,
                baseURL: baseURL,
                libraryDestURL: libraryDestURL,
                downloader: downloader,
                logger: logger
            ) else {
                // Non-fatal: log already emitted inside fetchOneVersion.
                continue
            }

            for pkg in pkgs {
                byID[pkg.packageID] = pkg
            }
        }

        // Return in a stable order matching AudioApplication sort: essential, core, optional; then by name.
        return byID.values.sorted {
            if $0.isEssential != $1.isEssential { return $0.isEssential }
            if $0.isCore      != $1.isCore      { return $0.isCore }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }


    // MARK: - Per-version fetch

    /// Download, extract, and parse one incremental DB archive.
    /// Returns `nil` on non-fatal failure (error already logged).
    private static func fetchOneVersion(
        version: Int,
        baseURL: URL,
        libraryDestURL: URL,
        downloader: DownloadClient,
        logger: CoreLogger
    ) async -> [AudioContentPackage]? {
        let paddedVersion = String(format: "%04d", version)
        let archiveName    = "contentDB_v\(paddedVersion)\(Consts.archiveSuffix)"
        let archiveRelPath = "\(Consts.archiveRelPathPrefix)\(paddedVersion)\(Consts.archiveSuffix)"
        var downloadURL = baseURL
        for part in archiveRelPath.split(separator: "/") {
            downloadURL.appendPathComponent(String(part))
        }

        logger.debug("IncrementalDBFetcher: downloading '\(downloadURL.absoluteString)'")

        // 1) Download to a temp file.
        let tempArchiveURL: URL
        do {
            tempArchiveURL = try await downloader.downloadTempFile(
                from: downloadURL,
                maxRetries: 2,
                retryDelay: 2,
                minimumBandwidth: nil,
                bandwidthWindow: 60,
                onRetry: { attempt, max, error in
                    logger.warning("IncrementalDBFetcher: retry \(attempt)/\(max) for \(archiveName): \(error.localizedDescription)")
                }
            )
        } catch {
            logger.error("IncrementalDBFetcher: download failed for v\(version): \(error.localizedDescription)")
            return nil
        }

        defer { try? FileManager.default.removeItem(at: tempArchiveURL) }

        // 2) Create a temp directory for extraction.
        let tempDir: URL
        do {
            tempDir = try FileManager.default.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: FileManager.default.temporaryDirectory,
                create: true
            )
        } catch {
            logger.error("IncrementalDBFetcher: failed to create temp dir for v\(version): \(error.localizedDescription)")
            return nil
        }

        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 3) Extract via /usr/bin/aa.
        let extracted = extractArchive(
            archiveURL: tempArchiveURL,
            destinationURL: tempDir,
            version: version,
            logger: logger
        )

        guard extracted else { return nil }

        // 4) Find the contentDB_vXXXX.bundle directory inside the temp dir.
        guard let bundleURL = findBundleDirectory(in: tempDir, version: version, logger: logger) else {
            return nil
        }

        // 5) Parse Package.plist.
        let pkgs = IncrementalContentDatabase.packages(
            inBundleAt: bundleURL,
            libraryDestURL: libraryDestURL,
            logger: logger
        )

        logger.debug("IncrementalDBFetcher: v\(version) yielded \(pkgs.count) package(s)")
        return pkgs
    }


    // MARK: - aa extract

    /// Run `/usr/bin/aa extract -d <dest> -i <archive>`. Returns true on success.
    private static func extractArchive(
        archiveURL: URL,
        destinationURL: URL,
        version: Int,
        logger: CoreLogger
    ) -> Bool {
        let cmd = [
            Consts.aaPath,
            "extract",
            "-d", destinationURL.path,
            "-i", archiveURL.path
        ]

        logger.debug("IncrementalDBFetcher: extracting v\(version) to '\(destinationURL.path)'")

        let result: CompletedProcess
        do {
            result = try ProcessRunner.run(cmd, captureOutput: true, check: false, debugLog: logger.debug)
        } catch {
            logger.error("IncrementalDBFetcher: failed to launch aa for v\(version): \(error.localizedDescription)")
            return false
        }

        let stdout = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")

        if result.succeeded {
            if !combined.isEmpty { logger.debug(combined) }
            return true
        } else {
            if !combined.isEmpty { logger.error(combined) }
            logger.error("IncrementalDBFetcher: extraction failed for v\(version) (exit \(result.returnCode))")
            return false
        }
    }


    // MARK: - Bundle directory lookup

    /// Locate the `contentDB_vXXXX.bundle` directory produced by extraction.
    private static func findBundleDirectory(
        in tempDir: URL,
        version: Int,
        logger: CoreLogger
    ) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.error("IncrementalDBFetcher: cannot enumerate '\(tempDir.path)'")
            return nil
        }

        let candidate = entries.first { url in
            guard let vals = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  vals.isDirectory == true
            else { return false }
            let name = url.lastPathComponent
            return name.hasPrefix(Consts.bundleDirPrefix) && name.hasSuffix(Consts.bundleDirSuffix)
        }

        if let candidate {
            logger.debug("IncrementalDBFetcher: found bundle '\(candidate.lastPathComponent)' for v\(version)")
        } else {
            logger.error("IncrementalDBFetcher: no '\(Consts.bundleDirPrefix)*\(Consts.bundleDirSuffix)' in '\(tempDir.path)' for v\(version)")
        }

        return candidate
    }


    // MARK: - Base URL helper

    private static func effectiveBaseURL(cacheServer: URL?, mirrorServer: URL?) -> URL {
        mirrorServer
            ?? cacheServer
            ?? LoopdownConstants.Downloads.contentSourceBaseURL
    }
}
