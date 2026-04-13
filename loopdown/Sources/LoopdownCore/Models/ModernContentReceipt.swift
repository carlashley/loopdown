//// ModernContentReceipt.swift
// loopdown
//
// Created on 12/4/2026
//
    


//// ModernContentReceipt.swift
// loopdown
//
// Created on 12/4/2026
//

import Foundation


// MARK: - ModernContentReceipt

/// Receipt plist for a modern Logic Pro 12+ / MainStage 4+ content package.
///
/// Located at:
///   `<libraryDestURL>/Application Support/Package Definitions/<packageStem>.plist`
///
/// The plist has the following keys (mirroring the Python `ModernContentReceipt` dataclass):
///
/// | Plist key          | Swift property    | Type               |
/// |--------------------|-------------------|--------------------|
/// | `Build`            | `build`           | `Int`              |
/// | `Bundle Identifier`| `bundleIdentifier`| `String`           |
/// | `Bundle Name`      | `bundleName`      | `String`           |
/// | `FileChecks`       | `fileChecks`      | `[String]`         |
/// | `PackageVersion`   | `packageVersion`  | `String`           |
/// | `Revision`         | `revision`        | `Int`              |
///
/// `FileChecks` may be a single `String` or an `Array<String>`; both are normalised
/// to `[String]`. The paths are relative to `libraryDestURL`.
public struct ModernContentReceipt: Sendable {

    public let build: Int
    public let bundleIdentifier: String
    public let bundleName: String

    /// Absolute file-check paths (relative plist paths resolved against `libraryDestURL`).
    public let fileChecks: [String]

    public let packageVersion: String
    public let revision: Int


    // MARK: - Factory

    /// Read the receipt plist for `packageStem` from under `libraryDestURL`.
    ///
    /// Returns `nil` if the file does not exist or cannot be decoded — callers
    /// must treat `nil` as "no receipt / not installed".
    ///
    /// - Parameters:
    ///   - packageStem: Filename stem of the downloaded package (e.g. `"apc_SomeArtistPack"`).
    ///   - libraryDestURL: Root of the Logic Pro Library bundle.
    public static func load(
        packageStem: String,
        libraryDestURL: URL
    ) -> ModernContentReceipt? {
        let receiptURL = libraryDestURL
            .appendingPathComponent("Application Support/Package Definitions")
            .appendingPathComponent(packageStem)
            .appendingPathExtension("plist")

        guard FileManager.default.fileExists(atPath: receiptURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: receiptURL)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dict = plist as? [String: Any] else { return nil }
            return ModernContentReceipt(from: dict, libraryDestURL: libraryDestURL)
        } catch {
            return nil
        }
    }


    // MARK: - Internal init from raw dict

    private init?(from dict: [String: Any], libraryDestURL: URL) {
        guard
            let build = dict["Build"] as? Int,
            let bundleIdentifier = dict["Bundle Identifier"] as? String,
            let bundleName = dict["Bundle Name"] as? String,
            let packageVersion = dict["PackageVersion"].map({ "\($0)" }),
            let revision = dict["Revision"] as? Int
        else {
            return nil
        }

        self.build = build
        self.bundleIdentifier = bundleIdentifier
        self.bundleName = bundleName
        self.packageVersion = packageVersion
        self.revision = revision

        // Normalise FileChecks: String or [String], paths relative to libraryDestURL.
        let base = libraryDestURL.path

        if let single = dict["FileChecks"] as? String {
            self.fileChecks = ["\(base)/\(single)"]
        } else if let array = dict["FileChecks"] as? [String] {
            self.fileChecks = array.map { "\(base)/\($0)" }
        } else {
            self.fileChecks = []
        }
    }
}
