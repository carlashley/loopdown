//// AudioApplication.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation


// MARK: - Audio Application errors
public enum ApplicationError: Error {
    case invalidDateString(String)
}


// MARK: AudioApplication model
/// Represents an installed Apple audio application (GarageBand, Logic Pro, MainStage)
/// and provides access to its downloadable content package metadata.
///
/// This is a Core model. It may read local metadata from the application bundle.
public final class AudioApplication: Hashable, @unchecked Sendable {

    public let name: String
    public let version: String
    public let path: URL
    public let lastModified: Date
    public let shortName: String?

    /// Raw 'Packages' dictionary from the metadata property list file.
    public var packages: [String: Any]? { packagesCache }

    /// Mandatory packages decoded from the metadata property list.
    public var mandatory: [AudioContentPackage] { decodedPackagesCache.mandatory }

    /// Optional (non-mandatory) packages decoded from the metadata property list.
    public var optional: [AudioContentPackage] { decodedPackagesCache.optional }

    // MARK: - Logger

    private let logger: CoreLogger

    // MARK: - Caches

    /// Cache for the packages property list payload.
    private lazy var packagesCache: [String: Any]? = {
        self.readMetadataSourceFile()
    }()

    /// Internal cache for decoded packages split by mandatory flag.
    private lazy var decodedPackagesCache: (
        mandatory: [AudioContentPackage],
        optional: [AudioContentPackage]
    ) = { self.decodePackagesByMandatoriness() }()


    // MARK: - Init

    public init(
        name: String,
        version: String,
        path: URL,
        lastModified: Date,
        logger: CoreLogger = NullLogger()
    ) {
        self.name = name
        self.version = version
        self.path = path
        self.lastModified = lastModified
        self.shortName = LoopdownConstants.Applications.shortName(for: name)
        self.logger = logger
    }

    /// Convenience init that accepts an ISO-8601 UTC string like: "2025-01-02T03:04:05Z"
    public convenience init(
        name: String,
        version: String,
        path: URL,
        lastModifiedISO8601UTC: String,
        logger: CoreLogger = NullLogger()
    ) throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        guard let date = iso.date(from: lastModifiedISO8601UTC) else {
            throw ApplicationError.invalidDateString(lastModifiedISO8601UTC)
        }

        self.init(name: name, version: version, path: path, lastModified: date, logger: logger)
    }


    // MARK: - Hashable

    public static func == (lhs: AudioApplication, rhs: AudioApplication) -> Bool {
        lhs.name == rhs.name &&
        lhs.version == rhs.version &&
        lhs.path == rhs.path &&
        lhs.lastModified == rhs.lastModified &&
        lhs.shortName == rhs.shortName
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(version)
        hasher.combine(path)
        hasher.combine(lastModified)
        hasher.combine(shortName)
    }


    // MARK: - Decode packages and split mandatory/optional

    /// Decode the raw `Packages` dictionary into `AudioContentPackage` and split by mandatoriness.
    ///
    /// Notes: If `IsMandatory` is missing from the package dict, the `AudioContentPackage` decoder
    /// should default it to `false`.
    private func decodePackagesByMandatoriness() -> (mandatory: [AudioContentPackage], optional: [AudioContentPackage]) {
        guard let raw = self.packages else {
            return (mandatory: [], optional: [])
        }

        let decoder = PropertyListDecoder()

        var mandatoryPkgs: [AudioContentPackage] = []
        var optionalPkgs: [AudioContentPackage] = []

        for (outerKey, value) in raw {
            guard let pkgDict = value as? [String: Any] else {
                logger.debug("Skipping package '\(outerKey)' because value is not a dictionary.")
                continue
            }

            do {
                let data = try PropertyListSerialization.data(
                    fromPropertyList: pkgDict,
                    format: .binary,
                    options: 0
                )

                let pkg = try decoder.decode(AudioContentPackage.self, from: data)

                if pkg.mandatory {
                    mandatoryPkgs.append(pkg)
                } else {
                    optionalPkgs.append(pkg)
                }
            } catch {
                logger.debug("Failed to decode package '\(outerKey)': \(error)")
                continue
            }
        }

        // Stable ordering for repeatable output.
        mandatoryPkgs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        optionalPkgs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return (mandatory: mandatoryPkgs, optional: optionalPkgs)
    }


    // MARK: - Find resource file

    /// Find the relevant property list file containing package metadata.
    /// Looks under `<Application.app>/Contents/Resources/`.
    private func findResourceFile() -> URL? {
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
            errorHandler: { [logger] url, error in
                logger.error("Error enumerating \(url.path): \(error)")
                return true
            }
        ) {
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "plist" else { continue }

                // Regular file check, avoid directories etc.
                if let vals = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                   vals.isRegularFile != true {
                    continue
                }

                let filename = url.lastPathComponent

                // Meta file pattern match.
                guard LoopdownConstants.Applications.metaFileRegex.firstMatch(
                    in: filename,
                    options: [],
                    range: NSRange(filename.startIndex..<filename.endIndex, in: filename)
                ) != nil else {
                    continue
                }

                // Any short name present in filename.
                guard LoopdownConstants.Applications.shortNames.contains(where: {
                    filename.localizedCaseInsensitiveContains($0)
                }) else {
                    continue
                }

                // Pick a deterministic "best" match.
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


    // MARK: - Read property list

    /// Read the metadata source file and return the 'Packages' value.
    private func readMetadataSourceFile() -> [String: Any]? {
        guard let resourceFile = findResourceFile() else {
            return nil
        }

        do {
            let data = try Data(contentsOf: resourceFile)

            var format: PropertyListSerialization.PropertyListFormat = .binary
            let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
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
