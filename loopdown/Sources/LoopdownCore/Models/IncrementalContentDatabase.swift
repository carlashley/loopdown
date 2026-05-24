//// IncrementalContentDatabase.swift
// loopdown
//
// Created on 23/5/2026
//

import Foundation


// MARK: - IncrementalContentDatabase

/// Parses the `Package.plist` found inside an unpacked incremental content DB bundle
/// (e.g. `contentDB_v0018.bundle/Package.plist`) into `AudioContentPackage` values.
///
/// Logic Pro and MainStage periodically ship new content that is not included in the
/// app bundle's SQLite database. On first launch, the app:
///
///   1. Reads the shipping `ShippingContentVersion` plain-text file from inside the
///      content database bundle.
///   2. Fetches `https://audiocontentdownload.apple.com/universal/contentversion.plist`
///      to learn the highest available version (`contentversionV4`, etc.).
///   3. Downloads `universal/contentDB_vXX.aar` for every version between
///      (shipping + 1) and the latest, inclusive.
///   4. Unpacks each archive; inside is a `contentDB_vXXXX.bundle/Package.plist`.
///
/// This type handles step 4: given the root URL of the unpacked bundle directory,
/// it locates `Package.plist` and converts each `attributes` entry into an
/// `AudioContentPackage`.
///
/// The `Package.plist` structure is:
/// ```
/// {
///     attributes = (
///         {
///             displayName = "Eko Soul";
///             downloadSize = 274291045;
///             identifier = "0056_afrobeats";
///             inAppPackage = 0;
///             installedSize = 300382811;
///             localizedDisplayName = "Eko Soul";
///             minimumSoCVersion = 0;
///             serverPath = "ml_0056_afrobeats/ml_0056_afrobeats.aar";
///             serverVersion = 1;
///             visibleInStoreFront = 0;
///         }
///     );
/// }
/// ```
///
/// Mirrors Python `IncrementalContentDB` in `models/incremental_content_db.py`.
public enum IncrementalContentDatabase {

    // MARK: - Package.plist filename

    private static let packagePlistName = "Package.plist"

    // MARK: - Public entry point

    /// Parse all packages from the `Package.plist` inside `bundleURL`.
    ///
    /// `bundleURL` is the directory that `/usr/bin/aa extract` produces, e.g.
    /// `.../contentDB_v0018.bundle`. This method locates `Package.plist` inside
    /// it (at the top level) and decodes the `attributes` array.
    ///
    /// - Parameters:
    ///   - bundleURL:       URL of the unpacked `contentDB_vXXXX.bundle` directory.
    ///   - libraryDestURL:  Root of the Logic Pro Library bundle; used for receipt lookup.
    ///   - logger:          Logger for debug output.
    /// - Returns: Array of decoded packages. Empty if the plist is missing or malformed.
    public static func packages(
        inBundleAt bundleURL: URL,
        libraryDestURL: URL,
        logger: CoreLogger = NullLogger()
    ) -> [AudioContentPackage] {
        let plistURL = bundleURL.appendingPathComponent(packagePlistName)

        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            logger.debug("IncrementalContentDatabase: Package.plist not found at '\(plistURL.path)'")
            return []
        }

        let root: [String: Any]

        do {
            let data = try Data(contentsOf: plistURL)
            let obj  = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dict = obj as? [String: Any] else {
                logger.debug("IncrementalContentDatabase: Package.plist root is not a dictionary")
                return []
            }
            root = dict
        } catch {
            logger.debug("IncrementalContentDatabase: failed to read Package.plist: \(error)")
            return []
        }

        guard let attributes = root["attributes"] as? [[String: Any]] else {
            logger.debug("IncrementalContentDatabase: 'attributes' key missing or wrong type")
            return []
        }

        var result: [AudioContentPackage] = []

        for attr in attributes {
            guard let pkg = package(from: attr, libraryDestURL: libraryDestURL, logger: logger) else {
                continue
            }
            result.append(pkg)
        }

        logger.debug("IncrementalContentDatabase: decoded \(result.count) package(s) from '\(bundleURL.lastPathComponent)'")
        return result
    }


    // MARK: - Single-entry decoder

    /// Decode one `attributes` dictionary entry into an `AudioContentPackage`.
    ///
    /// Key mapping:
    ///
    /// | Plist key             | Meaning                                        |
    /// |-----------------------|------------------------------------------------|
    /// | `identifier`          | Package ID (drives `ecp*/ccp*/optional` flags) |
    /// | `displayName`         | Human-readable name                            |
    /// | `localizedDisplayName`| Fallback display name if `displayName` absent  |
    /// | `serverPath`          | Relative download path (relative to modern prefix) |
    /// | `downloadSize`        | Download size in bytes                         |
    /// | `installedSize`       | Installed size in bytes                        |
    /// | `serverVersion`       | Version integer                                |
    private static func package(
        from attr: [String: Any],
        libraryDestURL: URL,
        logger: CoreLogger
    ) -> AudioContentPackage? {
        guard let identifier  = attr["identifier"]  as? String,
              let serverPath  = attr["serverPath"]   as? String
        else {
            logger.debug("IncrementalContentDatabase: skipping entry missing 'identifier' or 'serverPath'")
            return nil
        }

        let trimmedID = identifier.trimmingCharacters(in: .whitespacesAndNewlines)

        // Prefer displayName; fall back to localizedDisplayName; then identifier.
        let displayName: String = {
            if let s = attr["displayName"] as? String, !s.isEmpty { return s }
            if let s = attr["localizedDisplayName"] as? String, !s.isEmpty { return s }
            return trimmedID
        }()

        let downloadSize: Int64 = {
            if let n = attr["downloadSize"] as? Int   { return Int64(n) }
            if let n = attr["downloadSize"] as? Int64 { return n }
            return 0
        }()

        let installedSize: Int64 = {
            if let n = attr["installedSize"] as? Int   { return Int64(n) }
            if let n = attr["installedSize"] as? Int64 { return n }
            return 0
        }()

        let version: String? = {
            if let n = attr["serverVersion"] as? Int   { return String(n) }
            if let n = attr["serverVersion"] as? Int64 { return String(n) }
            if let s = attr["serverVersion"] as? String { return s }
            return nil
        }()

        let isEssential = trimmedID.hasPrefix("ecp")
        let isCore      = trimmedID.hasPrefix("ccp")
        let isOptional  = !isEssential && !isCore

        // Receipt lookup — same logic as AudioContentPackage.fromModernRow.
        let stem    = URL(fileURLWithPath: serverPath).deletingPathExtension().lastPathComponent
        let receipt = ModernContentReceipt.load(packageStem: stem, libraryDestURL: libraryDestURL)
        let fileCheck = receipt?.fileChecks ?? []

        if fileCheck.isEmpty {
            logger.debug("IncrementalContentDatabase: no receipt for '\(trimmedID)' — treating as not installed")
        }

        return AudioContentPackage(
            downloadName: serverPath,
            packageID: trimmedID,
            downloadSize: ByteSize(downloadSize),
            fileCheck: fileCheck,
            installedSize: ByteSize(installedSize),
            displayName: displayName,
            isEssential: isEssential,
            isCore: isCore,
            isOptional: isOptional,
            version: version,
            isLegacy: false,
            libraryDestURL: libraryDestURL
        )
    }
}

