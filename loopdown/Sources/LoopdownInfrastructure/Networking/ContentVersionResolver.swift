//// ContentVersionResolver.swift
// loopdown
//
// Created on 23/5/2026
//

import Foundation
import LoopdownCore


// MARK: - ContentVersionResolver

/// Determines which incremental content DB archives (`contentDB_vXX.aar`) need to be
/// downloaded for a modern Logic Pro 12+ / MainStage 4+ installation.
///
/// Logic Pro fetches `contentversion.plist` on first launch to discover any content
/// database updates that postdate the version shipped inside the app bundle. This type
/// replicates that lookup so that `loopdown` can fetch the same incremental packages.
///
/// **Typical flow**
///
/// 1. Read the plain-text `ShippingContentVersion` file from the installed app bundle.
/// 2. Fetch `https://audiocontentdownload.apple.com/universal/contentversion.plist`.
/// 3. Extract the highest `contentversionVX` value from the plist.
/// 4. Return the range `(shippingVersion + 1 ... latestVersion)` as integers.
///    An empty range means the app is already up to date.
///
/// The `ShippingContentVersion` file lives at:
///   `<app>/Contents/Resources/Library.bundle/<ContentDatabaseVXX.db>/ShippingContentVersion`
///
/// The `contentversion.plist` structure (as at 2026-05-23):
/// ```
/// {
///     contentversion     = 14;
///     contentversionV3   = 15;
///     contentversionV4   = 18;
///     downloadDatabaseFormat = aar;
///     incrementalFormat  = aar;
///     packageFormat      = aar;
/// }
/// ```
///
/// Mirrors Python `ContentVersionResolver` in `services/content_version_resolver.py`.
public enum ContentVersionResolver {

    // MARK: - Constants

    private enum Consts {
        static let contentVersionPlistURL  = LoopdownConstants.Downloads.IncrementalContentDB.contentVersionPlistURL
        static let shippingVersionFilename = LoopdownConstants.Downloads.IncrementalContentDB.shippingVersionFilename
        static let versionKeyPrefix        = LoopdownConstants.Downloads.IncrementalContentDB.versionKeyPrefix
    }


    // MARK: - Errors

    public enum ResolverError: Error, CustomStringConvertible {
        case noContentDatabaseBundle(appPath: String)
        case unreadableShippingVersion(path: String)
        case fetchFailed(url: URL, error: Error)
        case malformedContentVersionPlist

        public var description: String {
            switch self {
            case .noContentDatabaseBundle(let path):
                return "No content database bundle found in '\(path)'"
            case .unreadableShippingVersion(let path):
                return "Cannot read ShippingContentVersion from '\(path)'"
            case .fetchFailed(let url, let error):
                return "Failed to fetch '\(url)': \(error.localizedDescription)"
            case .malformedContentVersionPlist:
                return "contentversion.plist is missing or has an unexpected structure"
            }
        }
    }


    // MARK: - Public API

    /// Resolve the incremental content DB version numbers that are newer than
    /// the version shipped inside `appBundleURL`.
    ///
    /// - Parameters:
    ///   - appBundleURL: URL of the installed `.app` bundle (e.g. `/Applications/Logic Pro.app`).
    ///   - downloader:   Shared `DownloadClient` instance used to fetch `contentversion.plist`.
    ///   - logger:       Logger for debug output.
    /// - Returns: A (possibly empty) array of version integers to fetch, in ascending order.
    ///            Empty means the app bundle is already at the latest content version.
    /// - Throws:  `ResolverError` on any unrecoverable failure.
    public static func pendingVersions(
        for appBundleURL: URL,
        downloader: DownloadClient,
        logger: CoreLogger = NullLogger()
    ) async throws -> [Int] {
        let shippingVersion = try readShippingContentVersion(
            appBundleURL: appBundleURL,
            logger: logger
        )

        logger.debug("ContentVersionResolver: shipping version = \(shippingVersion)")

        let latestVersion = try await fetchLatestContentVersion(downloader: downloader, logger: logger)

        logger.debug("ContentVersionResolver: latest version = \(latestVersion)")

        guard latestVersion > shippingVersion else {
            logger.debug("ContentVersionResolver: no incremental updates needed")
            return []
        }

        let versions = Array((shippingVersion + 1) ... latestVersion)
        logger.debug("ContentVersionResolver: pending versions = \(versions)")
        return versions
    }


    // MARK: - Shipping version (local)

    /// Read the integer `ShippingContentVersion` from the content database bundle
    /// inside the app bundle.
    private static func readShippingContentVersion(
        appBundleURL: URL,
        logger: CoreLogger
    ) throws -> Int {
        guard let dbBundleURL = findContentDatabaseBundle(appBundleURL: appBundleURL, logger: logger) else {
            throw ResolverError.noContentDatabaseBundle(appPath: appBundleURL.path)
        }

        let versionFileURL = dbBundleURL.appendingPathComponent(Consts.shippingVersionFilename)

        guard FileManager.default.fileExists(atPath: versionFileURL.path) else {
            throw ResolverError.unreadableShippingVersion(path: versionFileURL.path)
        }

        do {
            let raw = try String(contentsOf: versionFileURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let v = Int(raw) else {
                throw ResolverError.unreadableShippingVersion(path: versionFileURL.path)
            }
            return v
        } catch let e as ResolverError {
            throw e
        } catch {
            throw ResolverError.unreadableShippingVersion(path: versionFileURL.path)
        }
    }

    /// Locate the `ContentDatabaseV*.db` bundle directory inside the app bundle,
    /// mirroring `AudioApplication.findContentDatabase` (but returning the bundle
    /// directory itself rather than the `index.db` inside it).
    private static func findContentDatabaseBundle(
        appBundleURL: URL,
        logger: CoreLogger
    ) -> URL? {
        let containerURL = appBundleURL.appendingPathComponent(
            LoopdownConstants.ModernApps.contentDatabaseContainerPath,
            isDirectory: true
        )

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: containerURL.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            return nil
        }

        let prefix   = LoopdownConstants.ModernApps.contentDatabaseDirPrefix
        let suffix   = LoopdownConstants.ModernApps.contentDatabaseDirSuffix

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = entries.filter { url in
            guard let vals = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  vals.isDirectory == true
            else { return false }
            let name = url.lastPathComponent
            return name.hasPrefix(prefix) && name.hasSuffix(suffix)
        }

        return candidates.max(by: {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        })
    }


    // MARK: - Latest version (remote)

    /// Fetch `contentversion.plist` and return the highest `contentversionVX` value.
    private static func fetchLatestContentVersion(downloader: DownloadClient, logger: CoreLogger) async throws -> Int {
        let url = Consts.contentVersionPlistURL
        logger.debug("ContentVersionResolver: fetching '\(url.absoluteString)'")

        let data: Data
        do {
            // Download to a temp file via DownloadClient (consistent with all other HTTP in loopdown),
            // read contents, then discard the temp file.
            let tempURL = try await downloader.downloadTempFile(from: url, maxRetries: 2, retryDelay: 2)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            data = try Data(contentsOf: tempURL)
        } catch {
            throw ResolverError.fetchFailed(url: url, error: error)
        }

        let obj: Any
        do {
            obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw ResolverError.malformedContentVersionPlist
        }

        guard let dict = obj as? [String: Any] else {
            throw ResolverError.malformedContentVersionPlist
        }

        // Gather all keys that begin with "contentversion" and whose value is numeric.
        // This catches both `contentversion` (no suffix) and `contentversionV3`,
        // `contentversionV4`, etc. without hard-coding specific key names.
        var highest = 0

        for (key, value) in dict {
            guard key.hasPrefix(Consts.versionKeyPrefix) else { continue }
            let v: Int? = {
                if let n = value as? Int   { return n }
                if let n = value as? Int64 { return Int(n) }
                if let s = value as? String { return Int(s) }
                return nil
            }()
            guard let v else { continue }
            if v > highest { highest = v }
        }

        guard highest > 0 else {
            throw ResolverError.malformedContentVersionPlist
        }

        return highest
    }
}
