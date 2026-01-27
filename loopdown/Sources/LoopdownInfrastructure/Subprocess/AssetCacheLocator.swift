//// AssetCacheLocator.swift
// loopdown
//
// Created on 27/1/2026
//
    

import Foundation


// MARK: - Apple Asset Cache discovery
public enum AssetCacheLocator {

    // MARK: Constants
    private enum Consts {
        static let toolPath = "/usr/bin/AssetCacheLocatorUtil"
        static let defaultPreferredRank = 0
        static let minRank = 0
        static let maxRank = 10_000
        static let validSources: Set<String> = ["system"]
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

    // MARK: - Server health check (Python parity)

    static func isServerHealthy(
        _ server: [String: Any],
        minimumRanking: Int? = nil,
        ignoreFavoured: Bool = false
    ) -> Bool {

        let minRank = minimumRanking ?? Consts.defaultPreferredRank
        guard (Consts.minRank...Consts.maxRank).contains(minRank) else {
            return false
        }

        let healthy = server["healthy"] as? Bool ?? false

        let favoured: Bool?
        if ignoreFavoured {
            favoured = true
        } else {
            favoured = server["favored"] as? Bool
        }

        let rank: Int? = {
            if let i = server["rank"] as? Int { return i }
            if let d = server["rank"] as? Double { return Int(d) }
            return nil
        }()

        guard healthy, let rank else { return false }

        if favoured == nil {
            return rank >= minRank
        }

        return favoured == true && rank >= minRank
    }

    // MARK: - Extract cache server

    /// Extract a usable cache server URL (mirrors Python `extract_cache_server`)
    public static func extractCacheServerURL(
        source: String = "system",
        minimumRanking: Int? = nil,
        ignoreFavoured: Bool = false,
        scheme: String = "http",
        debugLog: ((String) -> Void)? = nil
    ) -> URL? {

        guard Consts.validSources.contains(source) else {
            debugLog?("Invalid cache source '\(source)'")
            return nil
        }

        guard let data = assetCacheLocatorJSON(debugLog: debugLog) else {
            debugLog?("No AssetCacheLocatorUtil data available")
            return nil
        }

        guard
            let results = data["results"] as? [String: Any],
            let sourceMeta = results[source] as? [String: Any],
            let savedServers = sourceMeta["saved servers"] as? [String: Any],
            var allServers = savedServers["all servers"] as? [[String: Any]]
        else {
            debugLog?("Unable to extract server list from AssetCacheLocatorUtil output")
            return nil
        }

        // Sort by rank (lowest first) – same as Python
        if allServers.count > 1 {
            allServers.sort {
                let r1 = ($0["rank"] as? Int) ?? Int.max
                let r2 = ($1["rank"] as? Int) ?? Int.max
                return r1 < r2
            }
        }

        for server in allServers {
            guard isServerHealthy(
                server,
                minimumRanking: minimumRanking,
                ignoreFavoured: ignoreFavoured
            ) else {
                continue
            }

            guard let hostport = server["hostport"] as? String else {
                continue
            }

            // hostport is usually "host:port" with no scheme
            var comps = URLComponents()
            comps.scheme = scheme

            if let idx = hostport.lastIndex(of: ":"),
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
