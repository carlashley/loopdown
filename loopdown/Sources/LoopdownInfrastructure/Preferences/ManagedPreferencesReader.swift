//// ManagedPreferencesReader.swift
// loopdown
//
// Created on 27/3/2026
//
    

import Foundation
import LoopdownCore


// MARK: - ManagedPreferencesReader

/// Reads managed preferences from the `com.github.carlashley.loopdown` CFPreferences domain
/// and returns a fully-populated `ManagedPreferences` value.
///
/// `CFPreferencesCopyAppValue` is used throughout so that MDM-pushed values (the managed
/// preferences layer) take precedence over any local `defaults write` values in the same
/// domain, matching the standard macOS preferences precedence order.
///
/// Preferences are read fresh on each `read()` call so that MDM profile pushes take effect
/// without restarting the binary.
///
/// ## Sane defaults (applied when keys are absent)
///
/// - `apps`               → all installed apps (empty array passed to ContentCoordinator)
/// - `required`+`optional` both absent/false → `required = true`
/// - `cacheServer`+`mirrorServer` both absent → `cacheServer = .auto`
/// - `forceDeploy`        → false
/// - `skipSignatureCheck` → false
/// - `logLevel`           → .info
/// - `dryRun`             → false  (also overridable by --dry-run CLI flag)
/// - `quietRun`           → false
public enum ManagedPreferencesReader {

    public static let domain = "com.github.carlashley.loopdown"

    // MARK: - Read

    /// Read and return managed preferences with all defaults applied.
    public static func read() -> ManagedPreferences {
        // Apps
        let apps = readApps()

        // Content selection — default required=true when both absent/false
        let rawRequired = bool(forKey: "required")
        let rawOptional = bool(forKey: "optional")
        let (required, optional): (Bool, Bool) = {
            if rawRequired == nil && rawOptional == nil {
                // Neither key present — default to required only
                return (true, false)
            }
            return (rawRequired ?? false, rawOptional ?? false)
        }()

        // Server — default cacheServer=.auto when both absent
        let cacheServer  = readCacheServer()
        let mirrorServer = readMirrorServer()
        let resolvedCacheServer: CacheServer? = {
            if mirrorServer != nil {
                // Mirror takes precedence; cacheServer is irrelevant
                return nil
            }
            // If neither key was present, default to .auto
            return cacheServer ?? .auto
        }()

        // Scalar flags
        let forceDeploy        = bool(forKey: "forceDeploy")        ?? false
        let skipSignatureCheck = bool(forKey: "skipSignatureCheck") ?? false
        let logLevel           = readLogLevel()
        let dryRun             = bool(forKey: "dryRun")             ?? false
        let quietRun           = bool(forKey: "quietRun")           ?? false

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

    private static func readApps() -> [ConcreteApp] {
        guard let raw = CFPreferencesCopyAppValue("apps" as CFString, domain as CFString)
                as? [String] else { return [] }
        return raw.compactMap { ConcreteApp(rawValue: $0.lowercased()) }
    }

    private static func readCacheServer() -> CacheServer? {
        guard let raw = CFPreferencesCopyAppValue("cacheServer" as CFString, domain as CFString)
                as? String, !raw.isEmpty else { return nil }
        if raw.lowercased() == "auto" { return .auto }
        guard let url = URL(string: raw), url.scheme != nil else { return nil }
        return .url(url)
    }

    private static func readMirrorServer() -> MirrorServer? {
        guard let raw = CFPreferencesCopyAppValue("mirrorServer" as CFString, domain as CFString)
                as? String, !raw.isEmpty else { return nil }
        return MirrorServer(urlString: raw)
    }

    private static func readLogLevel() -> AppLogLevel {
        guard let raw = CFPreferencesCopyAppValue("logLevel" as CFString, domain as CFString)
                as? String else { return .info }
        return AppLogLevel(parsing: raw) ?? .info
    }

    /// Read a Bool value. Returns nil if the key is absent (distinguishes absent from false).
    private static func bool(forKey key: String) -> Bool? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool
    }
}
