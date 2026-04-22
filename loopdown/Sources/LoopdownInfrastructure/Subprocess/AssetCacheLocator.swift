//// AssetCacheLocator.swift
// LoopdownInfrastructure
//
// Created on 27/1/2026
//

import Foundation


// MARK: - Apple Asset Cache discovery
public enum AssetCacheLocator {

    // MARK: Constants
    private enum Consts {
        static let toolPath             = "/usr/bin/AssetCacheLocatorUtil"
        static let defaultPreferredRank = 0
        static let validSources: Set<String> = ["system", "current_user"]
        static let validUntilFormat     = "yyyy-MM-dd HH:mm:ss z"
    }

    // MARK: - Run AssetCacheLocatorUtil

    /// Subprocess `/usr/bin/AssetCacheLocatorUtil --json`
    static func assetCacheLocatorJSON(
        debugLog: ((String) -> Void)? = nil
    ) -> [String: Any]? {

        guard FileManager.default.isExecutableFile(atPath: Consts.toolPath) else {
            debugLog?("AssetCacheLocatorUtil not found at \(Consts.toolPath)")
            return nil
        }

        let cmd = [Consts.toolPath, "--json"]

        do {
            let result = try ProcessRunner.run(
                cmd,
                captureOutput: true,
                check: true,
                debugLog: debugLog
            )

            let obj = try JSONSerialization.jsonObject(with: result.stdout)
            guard let root = obj as? [String: Any] else {
                debugLog?("AssetCacheLocatorUtil JSON root is not a dictionary")
                return nil
            }

            return root
        } catch let e as ProcessRunnerError {
            debugLog?("AssetCacheLocatorUtil failed: \(e)")
            return nil
        } catch {
            debugLog?("JSON decode error from AssetCacheLocatorUtil: \(error)")
            return nil
        }
    }

    // MARK: - Server candidate check

    /// Determine if a caching server entry is a usable candidate.
    ///
    /// Priority (all return true when rank >= minRank):
    ///   1. healthy + valid + favored
    ///   2. healthy + valid (not favored)
    ///   3. healthy (not valid or no validUntil)
    ///
    /// Matches Python `cache_server_is_candidate`.
    static func isServerCandidate(
        _ server: [String: Any],
        minimumRanking: Int = Consts.defaultPreferredRank,
        debugLog: ((String) -> Void)? = nil
    ) -> Bool {
        let healthy = server["healthy"] as? Bool ?? false
        guard healthy else { return false }

        let rank: Int = {
            if let i = server["rank"] as? Int    { return i }
            if let d = server["rank"] as? Double { return Int(d) }
            return Int.max
        }()

        guard rank >= minimumRanking else { return false }

        let favored = server["favored"] as? Bool

        // Parse validUntil from advice dict
        let valid: Bool = {
            guard let advice  = server["advice"] as? [String: Any],
                  let vldStr  = advice["validUntil"] as? String else { return false }

            debugLog?("Candidate cache server is valid until: '\(vldStr)'")

            let fmt = DateFormatter()
            fmt.dateFormat = Consts.validUntilFormat
            fmt.locale = Locale(identifier: "en_US_POSIX")

            guard let vldDate = fmt.date(from: vldStr) else {
                debugLog?("Error converting 'validUntil' to date (ignoring value): '\(vldStr)'")
                return false
            }

            return vldDate > Date()
        }()

        if valid && favored == true {
            debugLog?("Candidate cache server is healthy: \(healthy), ranked: \(rank), favoured: true")
            return true
        } else if valid {
            debugLog?("Candidate cache server is healthy: \(healthy), ranked: \(rank)")
            return true
        } else {
            // healthy but not valid or no validUntil — still a candidate
            debugLog?("Candidate cache server is healthy: \(healthy)")
            return true
        }
    }

    // MARK: - Extract cache server

    /// Extract a usable cache server URL from `AssetCacheLocatorUtil` output.
    ///
    /// Uses the `shared caching` key under `saved servers`, matching the Python
    /// `extract_cache_server` implementation.
    public static func extractCacheServerURL(
        source: String = "system",
        minimumRanking: Int? = nil,
        scheme: String = "http",
        debugLog: ((String) -> Void)? = nil
    ) -> URL? {

        guard Consts.validSources.contains(source) else {
            debugLog?("Invalid cache source '\(source)'; must be 'system' or 'current_user'")
            return nil
        }

        guard let data = assetCacheLocatorJSON(debugLog: debugLog) else {
            debugLog?("No AssetCacheLocatorUtil data available")
            return nil
        }

        // Python: metadata["results"][source]["saved servers"]["shared caching"]
        guard
            let results      = data["results"]       as? [String: Any],
            let sourceMeta   = results[source]        as? [String: Any],
            let savedServers = sourceMeta["saved servers"] as? [String: Any],
            var servers      = savedServers["shared caching"] as? [[String: Any]]
        else {
            debugLog?("Unable to extract 'shared caching' server list from AssetCacheLocatorUtil output")
            return nil
        }

        debugLog?("Found saved servers in 'AssetCacheLocatorUtil' output")

        // Sort by rank ascending, matching Python behaviour
        if servers.count > 1 {
            servers.sort {
                let r1 = ($0["rank"] as? Int) ?? Int.max
                let r2 = ($1["rank"] as? Int) ?? Int.max
                return r1 < r2
            }
        }

        let minRank = minimumRanking ?? Consts.defaultPreferredRank

        for server in servers {
            guard isServerCandidate(server, minimumRanking: minRank, debugLog: debugLog) else {
                continue
            }

            guard let hostport = server["hostport"] as? String else { continue }

            // hostport is "host:port" with no scheme
            var comps = URLComponents()
            comps.scheme = scheme

            if let idx  = hostport.lastIndex(of: ":"),
               let port = Int(hostport[hostport.index(after: idx)...]) {
                comps.host = String(hostport[..<idx])
                comps.port = port
            } else {
                comps.host = hostport
            }

            return comps.url
        }

        return nil
    }
}
