//// ManagedPreferencesReader.swift
// loopdown
//
// Created on 27/3/2026
//

import Foundation
import LoopdownCore


// MARK: - ManagedPreferencesReader

/// Reads managed preferences and returns a fully-populated `ManagedPreferences` value.
///
/// ## Source precedence
///
/// 1. `/Library/Managed Preferences/com.github.carlashley.loopdown.plist` — written by a DDM
///    script, MDM command, or any tooling that cannot use classic profile delivery. If this file
///    exists and is readable it is used exclusively.
/// 2. `CFPreferencesCopyAppValue` against the `com.github.carlashley.loopdown` domain — the
///    classic MDM managed-preferences stack (pushed via `com.apple.managed.preferences` profile
///    payload). Used when the plist file is absent.
///
/// Preferences are read fresh on each `read()` call so that changes take effect without
/// restarting the binary.
///
/// ## Sane defaults (applied when keys are absent)
///
/// - `apps`                                                                          → all installed apps (empty array passed to ContentCoordinator)
/// - `required`+`optional` both absent/false            → `required = true`
/// - `cacheServer`+`mirrorServer` both absent     → `cacheServer = .auto`
/// - `forceDeploy`                                                          → false
/// - `skipSignatureCheck`                                          → false
/// - `logLevel`                                                                → .info
/// - `dryRun`                                                                     → false  (also overridable by --dry-run CLI flag)
/// - `quietRun`                                                                 → false
public enum ManagedPreferencesReader {

    public static let domain   = BuildInfo.identifier
    public static let plistURL = URL(fileURLWithPath: "/Library/Managed Preferences/\(BuildInfo.identifier).plist")

    // MARK: - Read

    /// Read and return managed preferences with all defaults applied.
    public static func read() -> ManagedPreferences {
        if let dict = loadPlist() {
            return build(source: .plist(dict))
        }
        return build(source: .cfPreferences)
    }

    // MARK: - Plist loader

    /// Attempt to load the DDM-written plist. Returns nil if the file is absent or unreadable.
    private static func loadPlist() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: plistURL.path),
              let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data,
                                                                     format: nil) as? [String: Any]
        else { return nil }
        return dict
    }

    // MARK: - Builder

    private enum Source {
        case plist([String: Any])
        case cfPreferences
    }

    /// Construct a `ManagedPreferences` from whichever source was selected.
    private static func build(source: Source) -> ManagedPreferences {
        // Apps
        let apps = readApps(source: source)

        // Content selection — default required=true when both absent/false
        let rawRequired = bool(forKey: "required", source: source)
        let rawOptional = bool(forKey: "optional", source: source)
        let (required, optional): (Bool, Bool) = {
            if rawRequired == nil && rawOptional == nil {
                // Neither key present — default to required only
                return (true, false)
            }
            return (rawRequired ?? false, rawOptional ?? false)
        }()

        // Server — default cacheServer=.auto when both absent
        let cacheServer  = readCacheServer(source: source)
        let mirrorServer = readMirrorServer(source: source)
        let resolvedCacheServer: CacheServer? = {
            if mirrorServer != nil {
                // Mirror takes precedence; cacheServer is irrelevant
                return nil
            }
            // If neither key was present, default to .auto
            return cacheServer ?? .auto
        }()

        // Scalar flags
        let forceDeploy        = bool(forKey: "forceDeploy",        source: source) ?? false
        let skipSignatureCheck = bool(forKey: "skipSignatureCheck", source: source) ?? false
        let logLevel           = readLogLevel(source: source)
        let dryRun             = bool(forKey: "dryRun",             source: source) ?? false
        let quietRun           = bool(forKey: "quietRun",           source: source) ?? false

        return ManagedPreferences(
            apps:                apps,
            required:            required,
            optional:            optional,
            forceDeploy:         forceDeploy,
            skipSignatureCheck:  skipSignatureCheck,
            logLevel:            logLevel,
            cacheServer:         resolvedCacheServer,
            mirrorServer:        mirrorServer,
            dryRun:              dryRun,
            quietRun:            quietRun
        )
    }

    // MARK: - Key readers

    private static func readApps(source: Source) -> [ConcreteApp] {
        guard let raw = array(forKey: "apps", source: source) as? [String] else { return [] }
        return raw.compactMap { ConcreteApp(rawValue: $0.lowercased()) }
    }

    private static func readCacheServer(source: Source) -> CacheServer? {
        guard let raw = string(forKey: "cacheServer", source: source), !raw.isEmpty else { return nil }
        if raw.lowercased() == "auto" { return .auto }
        guard let url = URL(string: raw), url.scheme != nil else { return nil }
        return .url(url)
    }

    private static func readMirrorServer(source: Source) -> MirrorServer? {
        guard let raw = string(forKey: "mirrorServer", source: source), !raw.isEmpty else { return nil }
        return MirrorServer(urlString: raw)
    }

    private static func readLogLevel(source: Source) -> AppLogLevel {
        guard let raw = string(forKey: "logLevel", source: source) else { return .info }
        return AppLogLevel(parsing: raw) ?? .info
    }

    // MARK: - Primitive accessors

    /// Read a String value from whichever source is active.
    private static func string(forKey key: String, source: Source) -> String? {
        switch source {
        case .plist(let dict):
            return dict[key] as? String
        case .cfPreferences:
            return CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? String
        }
    }

    /// Read an Array value from whichever source is active.
    private static func array(forKey key: String, source: Source) -> [Any]? {
        switch source {
        case .plist(let dict):
            return dict[key] as? [Any]
        case .cfPreferences:
            return CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? [Any]
        }
    }

    /// Read a Bool value. Returns nil if the key is absent (distinguishes absent from false).
    private static func bool(forKey key: String, source: Source) -> Bool? {
        switch source {
        case .plist(let dict):
            return dict[key] as? Bool
        case .cfPreferences:
            return CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool
        }
    }
}
