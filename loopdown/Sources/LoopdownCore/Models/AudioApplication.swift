//// AudioApplication.swift
// loopdown
//
// Created on 18/1/2026
//

import Foundation


// MARK: AudioApplication model
/// Represents an installed Apple audio application (GarageBand, Logic Pro, MainStage)
/// and provides access to its downloadable content package metadata.
///
/// **Legacy apps** (GarageBand; Logic Pro < 12; MainStage < 4):
///   Packages are decoded from a `.plist` resource file inside the application bundle.
///
/// **Modern apps** (Logic Pro >= 12; MainStage >= 4):
///   Packages are decoded from a SQLite database at
///   `Contents/Resources/Library.bundle/ContentDatabaseV01.db/index.db`
///   inside the application bundle. The receipt plist for each package is read from
///   `<libraryDestURL>/Application Support/Package Definitions/<stem>.plist` to determine
///   install state and file-check paths.
///
/// This is a Core model. It reads local metadata from the application bundle at init time.
public final class AudioApplication: Hashable, Sendable {

    public let name: String
    public let version: String
    public let path: URL
    public let shortName: String?

    /// Mandatory packages decoded from the metadata source.
    public let mandatory: [AudioContentPackage]

    /// Optional (non-mandatory) packages decoded from the metadata source.
    public let optional: [AudioContentPackage]

    // MARK: - Logger

    private let logger: CoreLogger


    // MARK: - Init

    public init(
        name: String,
        version: String,
        path: URL,
        libraryDestURL: URL,
        logger: CoreLogger = NullLogger()
    ) {
        self.name = name
        self.version = version
        self.path = path
        self.shortName = LoopdownConstants.Applications.shortName(for: name)
        self.logger = logger

        // Eagerly read and decode metadata so all stored properties are immutable
        // and the type can conform to Sendable without @unchecked.
        let decoded: (mandatory: [AudioContentPackage], optional: [AudioContentPackage])

        if AudioApplication.isModernised(shortName: shortName, version: version) {
            decoded = AudioApplication.loadModernPackages(
                path: path,
                shortName: shortName!,          // isModernised guarantees shortName is non-nil
                libraryDestURL: libraryDestURL,
                logger: logger
            )
        } else {
            let raw = AudioApplication.readMetadataSourceFile(path: path, logger: logger)
            decoded = AudioApplication.decodePackagesByMandatoriness(raw: raw, logger: logger)
        }

        self.mandatory = decoded.mandatory
        self.optional  = decoded.optional
    }


    // MARK: - Hashable

    public static func == (lhs: AudioApplication, rhs: AudioApplication) -> Bool {
        lhs.name == rhs.name &&
        lhs.version == rhs.version &&
        lhs.path == rhs.path &&
        lhs.shortName == rhs.shortName
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(version)
        hasher.combine(path)
        hasher.combine(shortName)
    }


    // MARK: - Modern vs legacy determination

    /// Whether this app uses the modern SQLite-based content delivery system.
    ///
    /// Returns `true` for Logic Pro >= 12 and MainStage >= 4.
    /// GarageBand is always legacy.
    public static func isModernised(shortName: String?, version: String) -> Bool {
        guard let shortName,
              let threshold = LoopdownConstants.ModernApps.minimumModernVersion[shortName]
        else {
            return false
        }
        return majorVersion(of: version) >= threshold
    }

    /// Parse the major version integer from a version string like `"12.1.2"`.
    public static func majorVersion(of version: String) -> Int {
        Int(version.split(separator: ".").first ?? "") ?? 0
    }


    // MARK: - Modern package loading (SQLite)

    private static func loadModernPackages(
        path: URL,
        shortName: String,
        libraryDestURL: URL,
        logger: CoreLogger
    ) -> (mandatory: [AudioContentPackage], optional: [AudioContentPackage]) {
        let dbURL = path.appendingPathComponent(
            LoopdownConstants.ModernApps.contentDatabaseRelativePath
        )

        logger.debug("Loading modern content database: '\(dbURL.path)'")

        let rows = ModernContentDatabase.allContent(
            databaseURL: dbURL,
            appShortName: shortName,
            logger: logger
        )

        if rows.isEmpty {
            logger.debug("No modern packages found for '\(shortName)' in '\(dbURL.path)'")
        }

        var mandatoryPkgs: [AudioContentPackage] = []
        var optionalPkgs: [AudioContentPackage]  = []

        for row in rows {
            guard let pkg = AudioContentPackage.fromModernRow(
                row,
                libraryDestURL: libraryDestURL,
                logger: logger
            ) else { continue }

            if pkg.mandatory {
                mandatoryPkgs.append(pkg)
            } else {
                optionalPkgs.append(pkg)
            }
        }

        mandatoryPkgs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        optionalPkgs.sort  { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return (mandatory: mandatoryPkgs, optional: optionalPkgs)
    }


    // MARK: - Legacy package loading (plist)

    /// Decode the raw `Packages` dictionary into `AudioContentPackage` and split by mandatoriness.
    private static func decodePackagesByMandatoriness(
        raw: [String: Any]?,
        logger: CoreLogger
    ) -> (mandatory: [AudioContentPackage], optional: [AudioContentPackage]) {
        guard let raw else {
            return (mandatory: [], optional: [])
        }

        var mandatoryPkgs: [AudioContentPackage] = []
        var optionalPkgs: [AudioContentPackage]  = []

        for (outerKey, value) in raw {
            guard let pkgDict = value as? [String: Any] else {
                logger.debug("Skipping package '\(outerKey)' because value is not a dictionary.")
                continue
            }

            guard let pkg = AudioContentPackage.fromLegacyDict(pkgDict, logger: logger) else {
                continue
            }

            if pkg.mandatory {
                mandatoryPkgs.append(pkg)
            } else {
                optionalPkgs.append(pkg)
            }
        }

        mandatoryPkgs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        optionalPkgs.sort  { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return (mandatory: mandatoryPkgs, optional: optionalPkgs)
    }


    // MARK: - Find resource file (legacy path)

    /// Find the relevant property list file containing package metadata.
    /// Looks under `<Application.app>/Contents/Resources/`.
    private static func findResourceFile(path: URL, logger: CoreLogger) -> URL? {
        let resourcesURL = path.appendingPathComponent(
            LoopdownConstants.Applications.resourceFilePath,
            isDirectory: true
        )

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resourcesURL.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            return nil
        }

        var best: URL? = nil

        if let enumerator = FileManager.default.enumerator(
            at: resourcesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                logger.error("Error enumerating \(url.path): \(error)")
                return true
            }
        ) {
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "plist" else { continue }

                if let vals = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                   vals.isRegularFile != true {
                    continue
                }

                let filename = url.lastPathComponent

                guard LoopdownConstants.Applications.metaFileRegex.firstMatch(
                    in: filename,
                    options: [],
                    range: NSRange(filename.startIndex..<filename.endIndex, in: filename)
                ) != nil else {
                    continue
                }

                guard LoopdownConstants.Applications.shortNames.contains(where: {
                    filename.localizedCaseInsensitiveContains($0)
                }) else {
                    continue
                }

                if best == nil ||
                    filename.localizedStandardCompare(best!.lastPathComponent) == .orderedDescending {
                    best = url
                }
            }
        }

        if let best {
            logger.debug("Found application resource file '\(best.path)'")
        } else {
            logger.debug("No matching application resource file found under '\(resourcesURL.path)'")
        }

        return best
    }


    // MARK: - Read property list (legacy path)

    /// Read the metadata source file and return the 'Packages' value.
    private static func readMetadataSourceFile(path: URL, logger: CoreLogger) -> [String: Any]? {
        guard let resourceFile = findResourceFile(path: path, logger: logger) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: resourceFile)

            let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )

            guard let dict = plist as? [String: Any] else {
                logger.error("Property List root is not a dictionary: '\(resourceFile.path)'")
                return nil
            }

            return dict["Packages"] as? [String: Any]
        } catch {
            logger.error("Unable to parse packages from '\(resourceFile.path)': \(error)")
            return nil
        }
    }
}


// MARK: - Extend AudioApplication to return .concreteApp
public extension AudioApplication {
    /// The concrete app identity derived from `shortName`.
    var concreteApp: ConcreteApp? {
        guard let shortName else { return nil }
        return ConcreteApp(rawValue: shortName)
    }
}
