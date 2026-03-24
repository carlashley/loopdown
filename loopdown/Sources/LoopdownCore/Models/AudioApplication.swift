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
/// This is a Core model. It may read local metadata from the application bundle.
public final class AudioApplication: Hashable, Sendable {

    public let name: String
    public let version: String
    public let path: URL
    public let shortName: String?

    /// Mandatory packages decoded from the metadata property list.
    public let mandatory: [AudioContentPackage]

    /// Optional (non-mandatory) packages decoded from the metadata property list.
    public let optional: [AudioContentPackage]

    // MARK: - Logger

    private let logger: CoreLogger


    // MARK: - Init

    public init(
        name: String,
        version: String,
        path: URL,
        logger: CoreLogger = NullLogger()
    ) {
        self.name = name
        self.version = version
        self.path = path
        self.shortName = LoopdownConstants.Applications.shortName(for: name)
        self.logger = logger

        // Eagerly read and decode metadata so all stored properties are immutable
        // and the type can conform to Sendable without @unchecked.
        let raw = AudioApplication.readMetadataSourceFile(path: path, logger: logger)
        let decoded = AudioApplication.decodePackagesByMandatoriness(raw: raw, logger: logger)
        self.mandatory = decoded.mandatory
        self.optional = decoded.optional
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


    // MARK: - Decode packages and split mandatory/optional

    /// Decode the raw `Packages` dictionary into `AudioContentPackage` and split by mandatoriness.
    ///
    /// Notes: If `IsMandatory` is missing from the package dict, the `AudioContentPackage` decoder
    /// should default it to `false`.
    private static func decodePackagesByMandatoriness(
        raw: [String: Any]?,
        logger: CoreLogger
    ) -> (mandatory: [AudioContentPackage], optional: [AudioContentPackage]) {
        guard let raw else {
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
