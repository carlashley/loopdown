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
///    payload). Used when the plist file is absent or unreadable.
///
/// Preferences are read fresh on each `read()` call so that changes take effect without
/// restarting the binary.
///
/// ## Sane defaults (applied when keys are absent)
///
/// - `apps`                                               → all installed apps (empty array)
/// - `essential`+`core`+`optional` all absent/false       → `essential = true`, `core = true`
/// - `appPolicies`                                        → [] (use global flags for all apps)
/// - `cacheServer`+`mirrorServer` both absent             → `cacheServer = .auto`
/// - `forceDeploy`                                        → false
/// - `skipSignatureCheck`                                 → false
/// - `logLevel`                                           → .info
/// - `dryRun`                                             → false  (also overridable by --dry-run)
/// - `quietRun`                                           → false
/// - `libraryDest`                                        → /Users/Shared
/// - `maxRetries`                                         → 3 (download retries)
/// - `retryDelay`                                         → 2 (delay between download retries)
/// - `minimumBandwidth`                                   → nil (no threshold)
/// - `bandwidthWindow`                                    → 60
/// - `abortAfter`                                         → 3
public enum ManagedPreferencesReader {

    public static let domain   = BuildInfo.identifier
    public static let plistURL = URL(fileURLWithPath: "/Library/Managed Preferences/\(BuildInfo.identifier).plist")

    // MARK: - Read

    /// Read and return managed preferences with all defaults applied.
    ///
    /// - Throws: `PlistError.unreadable` if the plist file exists but cannot be read due to
    ///   a permissions error or other I/O failure. The file being absent is not an error —
    ///   it falls through to CFPreferences. All other plist failures (malformed, not a
    ///   dictionary) are also treated as fallthrough with a debug log entry.
    public static func read(debugLog: ((String) -> Void)? = nil) throws -> ManagedPreferences {
        switch loadPlist(debugLog: debugLog) {
        case .success(let dict):
            debugLog?("ManagedPreferencesReader: using plist source '\(plistURL.path)'")
            return build(source: .plist(dict))
        case .failure(.unreadable(let e)):
            // File exists but could not be read — hard failure. The admin placed this file
            // intentionally; silently falling back to CFPreferences would be misleading.
            throw PlistError.unreadable(e)
        case .failure(let error):
            debugLog?("ManagedPreferencesReader: plist unavailable (\(error)); falling back to CFPreferences domain '\(domain)'")
            return build(source: .cfPreferences)
        }
    }

    // MARK: - Plist loader

    public enum PlistError: Error, CustomStringConvertible {
        case notFound
        case unreadable(Error)
        case malformed(Error)
        case notADictionary

        public var description: String {
            switch self {
            case .notFound:               return "file not found at '\(ManagedPreferencesReader.plistURL.path)'"
            case .unreadable(let e):      return "file unreadable (\(e))"
            case .malformed(let e):       return "plist parse error (\(e))"
            case .notADictionary:         return "plist root is not a dictionary"
            }
        }
    }

    private static func loadPlist(debugLog: ((String) -> Void)?) -> Result<[String: Any], PlistError> {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            return .failure(.notFound)
        }

        let data: Data
        do {
            data = try Data(contentsOf: plistURL)
        } catch {
            return .failure(.unreadable(error))
        }

        let obj: Any
        do {
            obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            return .failure(.malformed(error))
        }

        guard let dict = obj as? [String: Any] else {
            return .failure(.notADictionary)
        }

        return .success(dict)
    }

    // MARK: - Builder

    private enum Source {
        case plist([String: Any])
        case cfPreferences
    }

    private static func build(source: Source) -> ManagedPreferences {
        let apps = readApps(source: source)

        // Content selection — default essential=true and core=true when all three are absent/false.
        let rawEssential = bool(forKey: "essential", source: source)
        let rawCore      = bool(forKey: "core",      source: source)
        let rawOptional  = bool(forKey: "optional",  source: source)
        let (essential, core, optional): (Bool, Bool, Bool) = {
            if rawEssential == nil && rawCore == nil && rawOptional == nil {
                return (true, true, false)
            }
            return (rawEssential ?? false, rawCore ?? false, rawOptional ?? false)
        }()

        let appPolicies = readAppPolicies(source: source)

        let cacheServer  = readCacheServer(source: source)
        let mirrorServer = readMirrorServer(source: source)
        let resolvedCacheServer: CacheServer? = {
            if mirrorServer != nil { return nil }
            return cacheServer ?? .auto
        }()

        let forceDeploy        = bool(forKey: "forceDeploy",        source: source) ?? false
        let skipSignatureCheck = bool(forKey: "skipSignatureCheck",  source: source) ?? false
        let logLevel           = readLogLevel(source: source)
        let dryRun             = bool(forKey: "dryRun",              source: source) ?? false
        let quietRun           = bool(forKey: "quietRun",            source: source) ?? false
        let libraryDest        = string(forKey: "libraryDest",       source: source)
                                    ?? LoopdownConstants.ModernApps.defaultLibraryDestParent

        let maxRetries = {
            let v = int(forKey: "maxRetries", source: source) ?? 3
            return (1...10).contains(v) ? v : 3
        }()
        let retryDelay = {
            let v = int(forKey: "retryDelay", source: source) ?? 2
            return (1...5).contains(v) ? v : 2
        }()
        let minimumBandwidth: Int? = {
            guard let raw = string(forKey: "minimumBandwidth", source: source), !raw.isEmpty else { return nil }
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let bps: Int?
            if s.hasSuffix("MB"), let n = Int(s.dropLast(2).trimmingCharacters(in: .whitespaces)) {
                bps = n * 1024 * 1024
            } else if s.hasSuffix("KB"), let n = Int(s.dropLast(2).trimmingCharacters(in: .whitespaces)) {
                bps = n * 1024
            } else {
                bps = nil
            }
            guard let v = bps else { return nil }
            let minBps = 300 * 1024
            let maxBps = 5 * 1024 * 1024
            return (minBps...maxBps).contains(v) ? v : nil
        }()
        let bandwidthWindow = {
            let v = int(forKey: "bandwidthWindow", source: source) ?? 60
            return (30...120).contains(v) ? v : 60
        }()
        let abortAfter = {
            let v = int(forKey: "abortAfter", source: source) ?? 3
            return (2...5).contains(v) ? v : 3
        }()

        return ManagedPreferences(
            apps:                apps,
            essential:           essential,
            core:                core,
            optional:            optional,
            appPolicies:         appPolicies,
            forceDeploy:         forceDeploy,
            skipSignatureCheck:  skipSignatureCheck,
            logLevel:            logLevel,
            cacheServer:         resolvedCacheServer,
            mirrorServer:        mirrorServer,
            dryRun:              dryRun,
            quietRun:            quietRun,
            libraryDest:         libraryDest,
            maxRetries:          maxRetries,
            retryDelay:          retryDelay,
            minimumBandwidth:    minimumBandwidth,
            bandwidthWindow:     bandwidthWindow,
            abortAfter:          abortAfter
        )
    }

    // MARK: - Key readers

    private static func readApps(source: Source) -> [ConcreteApp] {
        guard let raw = array(forKey: "apps", source: source) as? [String] else { return [] }
        return raw.compactMap { ConcreteApp(rawValue: $0.lowercased()) }
    }

    /// Parse the `appPolicies` array. Entries with an unrecognised `app` value are silently skipped.
    private static func readAppPolicies(source: Source) -> [AppContentPolicy] {
        guard let raw = array(forKey: "appPolicies", source: source) else { return [] }
        // Cast element-by-element: PropertyListSerialization vends NSDictionary, not [String: Any],
        // so a direct cast of the whole array as [[String: Any]] silently fails.
        return raw.compactMap { element -> AppContentPolicy? in
            guard let entry     = element as? [String: Any],
                  let appRaw    = entry["app"]       as? String,
                  let app       = ConcreteApp(rawValue: appRaw.lowercased()),
                  let essential = entry["essential"] as? Bool,
                  let core      = entry["core"]      as? Bool,
                  let optional  = entry["optional"]  as? Bool
            else { return nil }
            return AppContentPolicy(app: app, essential: essential, core: core, optional: optional)
        }
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

    private static func string(forKey key: String, source: Source) -> String? {
        switch source {
        case .plist(let dict):
            return dict[key] as? String
        case .cfPreferences:
            return CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? String
        }
    }

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

    /// Read an Int value. Returns nil if the key is absent.
    private static func int(forKey key: String, source: Source) -> Int? {
        switch source {
        case .plist(let dict):
            return dict[key] as? Int
        case .cfPreferences:
            return CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Int
        }
    }
}
