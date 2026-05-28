//// RemotePlistFetcher.swift
// loopdown
//
// Created on 28/5/2026
//

import Foundation
import LoopdownCore


// MARK: - RemotePlistFetcher

/// Downloads the remote content property list for a legacy (pre-modernised) audio
/// application and returns packages present in the remote file that are absent from
/// the app's locally-known package set.
///
/// Background: legacy apps ship a `<name><version>.plist` (e.g. `garageband10412.plist`)
/// inside `<App>.app/Contents/Resources/`. Apple hosts a corresponding file at
/// `https://audiocontentdownload.apple.com/lp10_ms3_content_2016/<plistName>`
/// that may include additional "delta" packages not present in the bundled copy —
/// content added after the app was released. `loopdown` must include these in the
/// candidate set so they are considered for download and deployment.
///
/// `URLSession` transparently decompresses `Content-Encoding: gzip` responses, so
/// the `Data` returned by `DownloadClient` is always plain bytes regardless of how
/// the server delivers the file.
///
/// Downloaded plists are written to a `defer`-cleaned temporary file, matching the
/// cleanup pattern used by `IncrementalDBFetcher`.
///
/// Mirrors Python `RemotePlistFetcher` in `services/remote_plist_fetcher.py`.
public enum RemotePlistFetcher {

    // MARK: - Constants

    private enum Consts {
        /// Relative path directory for legacy content plists on the Apple CDN.
        /// Combines with `contentSourceBaseURL` to give the plist base URL, e.g.
        /// `https://audiocontentdownload.apple.com/lp10_ms3_content_2016/garageband10412.plist`.
        static let plistRelDir = LoopdownConstants.Downloads.ContentPaths.path2016
    }


    // MARK: - Public API

    /// Fetch and decode remote delta packages for each legacy app in `apps`.
    ///
    /// Each legacy app fetches its own remote plist independently. Modern apps
    /// (Logic Pro >= 12, MainStage >= 4) are silently skipped — they use the
    /// incremental content DB mechanism instead.
    ///
    /// Results are deduplicated by `packageID` across all apps; the first occurrence
    /// of a given ID wins (consistent with `mergePackagesAcrossApps` priority).
    ///
    /// - Parameters:
    ///   - apps:         All resolved `AudioApplication` values for this run.
    ///   - cacheServer:  Optional caching/proxy server (used in place of Apple CDN).
    ///   - mirrorServer: Optional mirror server (highest priority).
    ///   - downloader:   Shared `DownloadClient` instance.
    ///   - logger:       Logger for debug and error output.
    /// - Returns: Deduplicated delta packages across all legacy apps. Never throws.
    public static func fetchAll(
        apps: [AudioApplication],
        cacheServer: URL?,
        mirrorServer: URL?,
        downloader: DownloadClient,
        logger: CoreLogger = NullLogger()
    ) async -> [AudioContentPackage] {

        let legacyApps = apps.filter { !$0.isModernised }
        guard !legacyApps.isEmpty else { return [] }

        // Merged results: first occurrence of a given ID wins.
        var byID: [String: AudioContentPackage] = [:]

        for app in legacyApps {
            guard let pkgs = await fetchOneApp(
                app: app,
                cacheServer: cacheServer,
                mirrorServer: mirrorServer,
                downloader: downloader,
                logger: logger
            ) else {
                // Non-fatal: log already emitted inside fetchOneApp.
                continue
            }

            for pkg in pkgs where byID[pkg.packageID] == nil {
                byID[pkg.packageID] = pkg
            }
        }

        // Return in a stable order: essential first, then core, then optional; by name within each bucket.
        return byID.values.sorted {
            if $0.isEssential != $1.isEssential { return $0.isEssential }
            if $0.isCore      != $1.isCore      { return $0.isCore }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }


    // MARK: - Per-app fetch

    /// Download, parse, and return delta packages for a single legacy app.
    /// Returns `nil` on non-fatal failure (error already logged).
    private static func fetchOneApp(
        app: AudioApplication,
        cacheServer: URL?,
        mirrorServer: URL?,
        downloader: DownloadClient,
        logger: CoreLogger
    ) async -> [AudioContentPackage]? {

        // Resolve the plist filename from the app bundle's Contents/Resources directory,
        // using the same naming convention AudioApplication.findResourceFile uses.
        guard let plistName = resolveLocalPlistName(appPath: app.path, logger: logger) else {
            logger.debug("RemotePlistFetcher: no content plist found in '\(app.path.path)/\(LoopdownConstants.Applications.resourceFilePath)' for \(app.name)")
            return nil
        }

        let baseURL = effectiveBaseURL(cacheServer: cacheServer, mirrorServer: mirrorServer)
        var downloadURL = baseURL
        for part in "\(Consts.plistRelDir)/\(plistName)".split(separator: "/") {
            downloadURL.appendPathComponent(String(part))
        }

        logger.debug("RemotePlistFetcher: fetching '\(downloadURL.absoluteString)' for \(app.name)")

        // 1) Download to a temp file.
        let tempPlistURL: URL
        do {
            tempPlistURL = try await downloader.downloadTempFile(
                from: downloadURL,
                maxRetries: 2,
                retryDelay: 2,
                minimumBandwidth: nil,
                bandwidthWindow: 60,
                onRetry: { attempt, max, error in
                    logger.warning("RemotePlistFetcher: retry \(attempt)/\(max) for '\(plistName)': \(error.localizedDescription)")
                }
            )
        } catch {
            logger.debug("RemotePlistFetcher: download failed for '\(plistName)': \(error.localizedDescription)")
            return nil
        }

        defer { try? FileManager.default.removeItem(at: tempPlistURL) }

        // 2) Load the downloaded data.
        // URLSession transparently decompresses Content-Encoding: gzip responses, so
        // the file on disk is always plain bytes regardless of server encoding.
        guard let plistData = try? Data(contentsOf: tempPlistURL) else {
            logger.error("RemotePlistFetcher: cannot read downloaded file for '\(plistName)'")
            return nil
        }

        // 3) Deserialise the plist.
        let obj: Any
        do {
            obj = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        } catch {
            logger.error("RemotePlistFetcher: failed to deserialise '\(plistName)': \(error.localizedDescription)")
            return nil
        }

        guard let root = obj as? [String: Any] else {
            logger.error("RemotePlistFetcher: unexpected plist root type in '\(plistName)'")
            return nil
        }

        guard let packagesDict = root["Packages"] as? [String: Any] else {
            logger.debug("RemotePlistFetcher: no 'Packages' key in '\(plistName)'")
            return nil
        }

        // 4) Decode all packages from the remote plist using the same factory
        //    AudioApplication uses when reading the bundled local copy.
        var remotePkgs: [AudioContentPackage] = []
        for (outerKey, value) in packagesDict {
            guard let pkgDict = value as? [String: Any] else {
                logger.debug("RemotePlistFetcher: skipping '\(outerKey)' — value is not a dictionary")
                continue
            }
            if let pkg = AudioContentPackage.fromLegacyDict(pkgDict, logger: logger) {
                remotePkgs.append(pkg)
            }
        }

        // 5) Filter to packages not already present in this app's locally-known set.
        let knownIDs = Set((app.essential + app.core + app.optional).map { $0.packageID })
        let delta = remotePkgs.filter { !knownIDs.contains($0.packageID) }

        if delta.isEmpty {
            logger.debug("RemotePlistFetcher: no delta packages for \(app.name) from '\(plistName)'")
        } else {
            logger.debug("RemotePlistFetcher: \(delta.count) delta package(s) for \(app.name) from '\(plistName)'")
        }

        return delta
    }


    // MARK: - Plist name resolution

    /// Resolve the legacy content plist filename from the app bundle's Contents/Resources directory.
    ///
    /// Uses the same `metaFileRegex` and `shortNames` checks as `AudioApplication.findResourceFile`.
    /// Returns only the filename (e.g. `garageband10412.plist`), not the full path.
    private static func resolveLocalPlistName(appPath: URL, logger: CoreLogger) -> String? {
        let resourcesURL = appPath.appendingPathComponent(
            LoopdownConstants.Applications.resourceFilePath,
            isDirectory: true
        )

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: resourcesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.debug("RemotePlistFetcher: cannot enumerate '\(resourcesURL.path)'")
            return nil
        }

        return entries.first { url in
            guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  vals.isRegularFile == true
            else { return false }

            let filename = url.lastPathComponent

            guard filename.contains(LoopdownConstants.Applications.metaFileRegex) else { return false }

            return LoopdownConstants.Applications.shortNames.contains(where: {
                filename.localizedCaseInsensitiveContains($0)
            })
        }?.lastPathComponent
    }


    // MARK: - Base URL helper

    private static func effectiveBaseURL(cacheServer: URL?, mirrorServer: URL?) -> URL {
        mirrorServer
            ?? cacheServer
            ?? LoopdownConstants.Downloads.contentSourceBaseURL
    }
}
