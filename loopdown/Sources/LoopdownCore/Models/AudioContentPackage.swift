//// AudioContentPackage.swift
// loopdown
//
// Created on 18/1/2026
//

import Foundation


// MARK: - AudioContentPackage model

/// Audio content package metadata, covering both legacy (`.pkg`) and modern (`.aar`) packages.
///
/// **Legacy packages** (GarageBand, Logic Pro < 12, MainStage < 4):
///   - Decoded from a `.plist` resource file inside the application bundle.
///   - `isLegacy == true`, `libraryDestURL == nil`.
///   - Install state determined by `fileCheck` paths + `pkgutil` version comparison.
///   - Installed via `/usr/sbin/installer`.
///
/// **Modern packages** (Logic Pro >= 12, MainStage >= 4):
///   - Decoded from a SQLite database at
///     `<app>/Contents/Resources/Library.bundle/ContentDatabaseV01.db/index.db`.
///   - `isLegacy == false`, `libraryDestURL` is the Logic Pro Library bundle destination.
///   - Install state determined by `fileCheck` paths only (all must exist).
///   - `fileCheck` paths come from the receipt plist at
///     `<libraryDestURL>/Application Support/Package Definitions/<stem>.plist`.
///   - Installed by extracting via `/usr/bin/aa extract -d <libraryDestURL> -i <archive>`.
///
/// Hashing and equality are intentionally based only on `packageID`.
public struct AudioContentPackage: Hashable, Sendable, CustomStringConvertible {

    // MARK: - Stored properties

    public var downloadName: String
    public var packageID: String                      // Identity field
    public var downloadSize: ByteSize
    public var fileCheck: [String]                    // Absolute paths; may be empty
    public var installedSize: ByteSize
    public var mandatory: Bool
    public var version: String?

    /// `false` for modern Logic Pro 12+ / MainStage 4+ packages.
    public let isLegacy: Bool

    /// Destination root for modern package extraction (`aa extract -d <libraryDestURL>`).
    /// Always `nil` for legacy packages.
    public let libraryDestURL: URL?

    // MARK: - Derived properties

    public var name: String {
        URL(fileURLWithPath: downloadName).lastPathComponent
    }

    /// Normalized relative path for use when constructing the download URL and local file path.
    ///
    /// Both legacy and modern paths are expressed as a relative path that is appended to
    /// whatever server base is in effect (Apple CDN, cache server, or mirror). No per-package
    /// branching is needed in the coordinator — the server is always prepended uniformly.
    ///
    /// - Legacy: `PackagePathNormalizer` prepends `lp10_ms3_content_2016/` (or `_2013/`).
    /// - Modern: `LoopdownConstants.Downloads.ContentPaths.modernPrefix` is prepended to the
    ///   `ZSERVERPATH` value from the SQLite database, then the result is POSIX-normalized.
    ///   Mirrors `normalize_url_path(server_path, is_legacy=False)` in Python.
    public var downloadPath: String {
        if isLegacy {
            return PackagePathNormalizer.normalizePackageDownloadPath(downloadName)
        } else {
            let prefix = LoopdownConstants.Downloads.ContentPaths.modernPrefix
            // Mirrors posixpath.normpath("universal/ContentPacks_3/" + server_path).
            // Must not use NSString.standardizingPath — it prepends cwd on relative paths.
            return PackagePathNormalizer.posixNormalizePath("\(prefix)/\(downloadName)")
        }
    }

    public var description: String { name }


    // MARK: - Legacy factory (from plist dict)

    /// Decode a legacy package from a raw plist dictionary.
    public static func fromLegacyDict(
        _ dict: [String: Any],
        logger: CoreLogger = NullLogger()
    ) -> AudioContentPackage? {
        guard let downloadName = dict["DownloadName"] as? String,
              let packageID    = dict["PackageID"]    as? String
        else {
            logger.debug("Skipping package: missing DownloadName or PackageID")
            return nil
        }

        let downloadSize  = (dict["DownloadSize"]  as? Int64) ?? 0
        let installedSize = (dict["InstalledSize"] as? Int64) ?? 0
        let mandatory     = (dict["IsMandatory"]   as? Bool)  ?? false

        let version: String? = {
            if let s = dict["PackageVersion"] as? String { return s }
            if let i = dict["PackageVersion"] as? Int    { return String(i) }
            if let d = dict["PackageVersion"] as? Double {
                return d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(d)) : String(d)
            }
            return nil
        }()

        let fileCheck: [String] = {
            if let s = dict["FileCheck"] as? String   { return s.isEmpty ? [] : [s] }
            if let a = dict["FileCheck"] as? [String] { return a }
            return []
        }()

        return AudioContentPackage(
            downloadName: downloadName,
            packageID: packageID.trimmingCharacters(in: .whitespacesAndNewlines),
            downloadSize: ByteSize(downloadSize),
            fileCheck: fileCheck,
            installedSize: ByteSize(installedSize),
            mandatory: mandatory,
            version: version,
            isLegacy: true,
            libraryDestURL: nil
        )
    }


    // MARK: - Modern factory (from SQLite row)

    /// Construct a modern package from a SQLite row dict and the receipt plist.
    ///
    /// - Parameters:
    ///   - row: Column-value dictionary from the CTE query in `ModernContentDatabase`.
    ///   - libraryDestURL: Root URL of the Logic Pro Library bundle for receipt lookup and extraction.
    ///   - logger: Logger for debug output.
    public static func fromModernRow(
        _ row: [String: SQLiteValue],
        libraryDestURL: URL,
        logger: CoreLogger = NullLogger()
    ) -> AudioContentPackage? {
        guard let packageID    = row["package_id"]?.stringValue,
              let serverPath   = row["server_path"]?.stringValue,
              let downloadName = row["download_name"]?.stringValue
        else {
            logger.debug("Skipping modern row: missing package_id, server_path, or download_name")
            return nil
        }

        let downloadSize  = row["download_size"]?.intValue  ?? 0
        let installedSize = row["installed_size"]?.intValue ?? 0

        // mandatory = 1 when identifier starts with 'ccp' or 'ecp' (set by CTE CASE expression).
        let mandatory = (row["mandatory"]?.intValue ?? 0) != 0

        let version: String? = row["server_version"]?.intValue.map { String($0) }

        // The filename stem of download_name locates the receipt plist.
        let stem = URL(fileURLWithPath: downloadName).deletingPathExtension().lastPathComponent

        // Load the receipt to obtain fileCheck paths. Absence = not yet installed.
        let receipt = ModernContentReceipt.load(packageStem: stem, libraryDestURL: libraryDestURL)
        let fileCheck = receipt?.fileChecks ?? []

        if fileCheck.isEmpty {
            logger.debug("No receipt for '\(packageID)' — treating as not installed")
        }

        return AudioContentPackage(
            downloadName: serverPath,       // used verbatim as downloadPath for modern packages
            packageID: packageID.trimmingCharacters(in: .whitespacesAndNewlines),
            downloadSize: ByteSize(downloadSize),
            fileCheck: fileCheck,
            installedSize: ByteSize(installedSize),
            mandatory: mandatory,
            version: version,
            isLegacy: false,
            libraryDestURL: libraryDestURL
        )
    }


    // MARK: - Memberwise init (internal)

    internal init(
        downloadName: String,
        packageID: String,
        downloadSize: ByteSize,
        fileCheck: [String],
        installedSize: ByteSize,
        mandatory: Bool,
        version: String?,
        isLegacy: Bool,
        libraryDestURL: URL?
    ) {
        self.downloadName   = downloadName
        self.packageID      = packageID
        self.downloadSize   = downloadSize
        self.fileCheck      = fileCheck
        self.installedSize  = installedSize
        self.mandatory      = mandatory
        self.version        = version
        self.isLegacy       = isLegacy
        self.libraryDestURL = libraryDestURL
    }


    // MARK: - Hashable / Equatable (identity by packageID only)

    public func hash(into hasher: inout Hasher) {
        hasher.combine(packageID)
    }

    public static func == (lhs: AudioContentPackage, rhs: AudioContentPackage) -> Bool {
        lhs.packageID == rhs.packageID
    }
}
