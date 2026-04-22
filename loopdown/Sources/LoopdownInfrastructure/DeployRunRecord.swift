//// DeployRunRecord.swift
// loopdown
//
// Created on 16/4/2026
//

import Foundation
import LoopdownCore


// MARK: - DeployRunRecord

/// Persistent record of deploy runs, written as a property list to
/// `/Library/Application Support/<bundle id>/<bundle id>.last_deploy_run.plist`.
///
/// Structure: `apps > modern|legacy > <appName> > <category> > checked/installed`
///
/// Only apps that had at least one package installed in a given run are updated;
/// all other existing entries are preserved unchanged.
///
/// All dates are UTC ISO8601.
public struct DeployRunRecord: Codable {

    // MARK: - Installed package entry

    public struct InstalledPackage: Codable {
        public let id: String
        /// UTC timestamp of when this package was installed.
        public let installedDate: String

        public init(id: String, installedDate: String) {
            self.id            = id
            self.installedDate = installedDate
        }
    }

    // MARK: - Category breakdown

    public struct CategoryRecord: Codable {
        /// Package IDs that were selected and checked during this run.
        public var checked: [String]
        /// Packages that were successfully installed during this run.
        public var installed: [InstalledPackage]

        public init(checked: [String] = [], installed: [InstalledPackage] = []) {
            self.checked   = checked
            self.installed = installed
        }
    }

    // MARK: - Per-app record

    public struct AppRecord: Codable {
        /// UTC timestamp of when this app's content was last deployed.
        public var runDate: String
        /// Version of the app at the time of this deploy run.
        public var appVersion: String
        public var essential: CategoryRecord
        public var core: CategoryRecord
        public var optional: CategoryRecord

        public init(runDate: String, appVersion: String) {
            self.runDate    = runDate
            self.appVersion = appVersion
            self.essential  = CategoryRecord()
            self.core       = CategoryRecord()
            self.optional   = CategoryRecord()
        }

        // Omit categories whose checked and installed arrays are both empty.
        enum CodingKeys: String, CodingKey { case runDate, appVersion, essential, core, optional }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(runDate,    forKey: .runDate)
            try container.encode(appVersion, forKey: .appVersion)
            if !essential.checked.isEmpty || !essential.installed.isEmpty { try container.encode(essential, forKey: .essential) }
            if !core.checked.isEmpty      || !core.installed.isEmpty      { try container.encode(core,      forKey: .core)      }
            if !optional.checked.isEmpty  || !optional.installed.isEmpty  { try container.encode(optional,  forKey: .optional)  }
        }
    }

    // MARK: - Generation grouping

    public struct GenerationRecord: Codable {
        /// Keyed by `ConcreteApp.rawValue` (e.g. `"logicpro"`, `"mainstage"`).
        public var apps: [String: AppRecord]

        public init(apps: [String: AppRecord] = [:]) {
            self.apps = apps
        }
    }

    // MARK: - Top-level fields

    public var modern: GenerationRecord
    public var legacy: GenerationRecord
    /// UTC timestamp of the most recent deploy run overall.
    public var lastRunDate: String

    // MARK: - Init

    public init(lastRunDate: Date = Date()) {
        self.modern      = GenerationRecord()
        self.legacy      = GenerationRecord()
        self.lastRunDate = DeployRunRecord.utcFormatter.string(from: lastRunDate)
    }

    // Omit generation buckets that have no app entries.
    enum CodingKeys: String, CodingKey { case modern, legacy, lastRunDate }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lastRunDate, forKey: .lastRunDate)
        if !modern.apps.isEmpty { try container.encode(modern, forKey: .modern) }
        if !legacy.apps.isEmpty { try container.encode(legacy, forKey: .legacy) }
    }

    // MARK: - Subscript helpers

    /// Read/write an `AppRecord` by generation string and app key.
    public subscript(generation: String, appKey: String) -> AppRecord? {
        get {
            generation == "modern" ? modern.apps[appKey] : legacy.apps[appKey]
        }
        set {
            if generation == "modern" {
                modern.apps[appKey] = newValue
            } else {
                legacy.apps[appKey] = newValue
            }
        }
    }

    // MARK: - Merge and write

    /// Load any existing plist, merge in only the apps that had installs this run, then write.
    ///
    /// Apps absent from `updatedApps` are left untouched in the existing plist.
    /// Creates the parent directory if needed.
    public static func mergeAndWrite(updatedApps: [(generation: String, appKey: String, record: AppRecord)], runDate: Date = Date()) throws {
        let fm = FileManager.default

        // Load existing record if present, otherwise start fresh.
        var base = DeployRunRecord(lastRunDate: runDate)
        if fm.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL) {
                var existing = (try? PropertyListDecoder().decode(DeployRunRecord.self, from: data)) ?? DeployRunRecord()
                existing.lastRunDate = DeployRunRecord.utcFormatter.string(from: runDate)
                base = existing
            }
        }

        for (generation, appKey, record) in updatedApps {
            base[generation, appKey] = record
        }

        if !fm.fileExists(atPath: directoryURL.path) {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(base)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Paths

    public static let directoryURL = URL(
        fileURLWithPath: "/Library/Application Support/\(BuildInfo.identifier)",
        isDirectory: true
    )

    public static let fileURL = directoryURL
        .appendingPathComponent("\(BuildInfo.identifier).last_deploy_run.plist")

    // MARK: - Formatter

    public static let utcFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone      = TimeZone(identifier: "UTC")!
        return f
    }()
}
