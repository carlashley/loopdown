//// ServerArguments.swift
// loopdown
//
// Created on 18/1/2026
//

import ArgumentParser
import Foundation
import LoopdownInfrastructure


// MARK: - Server options

/// Grouped CLI arguments for cache and mirror server selection.
///
/// `CacheServer` and `MirrorServer` types are defined in `LoopdownInfrastructure/Networking/CacheServer.swift`.
/// Their `ExpressibleByArgument` conformances are in `CacheServer+ArgumentParser.swift`.
struct ServerOptions: ParsableArguments {
    @Option(name: [.customShort("c"), .long], help: "Caching server to use; 'auto' or http://host:port")
    var cacheServer: CacheServer?

    @Option(name: [.customShort("m"), .long], help: "Mirror server base URL")
    var mirrorServer: MirrorServer?

    mutating func validate() throws {
        if cacheServer != nil && mirrorServer != nil {
            throw ValidationError("Use either '--cache-server' or '--mirror-server', not both.")
        }

        if let cacheServer {
            try validateCacheServer(cacheServer)
        }
    }

    private func validateCacheServer(_ value: CacheServer) throws {
        switch value {
        case .auto:
            return
        case .url(let url):
            guard url.scheme?.lowercased() == "http" else {
                throw ValidationError("'--cache-server' must use http")
            }
            guard let host = url.host, !host.isEmpty else {
                throw ValidationError("Cache server must include a host")
            }
            guard let port = url.port, (1...65535).contains(port) else {
                throw ValidationError("Cache server must include a valid port")
            }
        }
    }
}


// MARK: - Cache auto-discovery options

/// Grouped CLI arguments controlling the behaviour of `--cache-server auto` discovery.
///
/// Applies to `deploy` command. Has no effect unless `--cache-server auto` is in use.
struct CacheAutoDiscoveryOptions: ParsableArguments {
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Maximum number of attempts when auto-discovering a caching server (default: 3).",
            valueName: "n"
        )
    )
    var cacheAutoRetries: Int? = nil

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Seconds to wait between caching server auto-discovery attempts (default: 1).",
            valueName: "seconds"
        )
    )
    var cacheRetryDelay: Int? = nil

    /// Effective value used at call sites; falls back to default when flag was not supplied.
    var effectiveCacheAutoRetries: Int { cacheAutoRetries ?? 3 }
    var effectiveCacheRetryDelay: Int  { cacheRetryDelay  ?? 1 }

    mutating func validate() throws {
        if let v = cacheAutoRetries, v < 1 {
            throw ValidationError("'--cache-auto-retries' must be at least 1.")
        }
        if let v = cacheRetryDelay, v < 0 {
            throw ValidationError("'--cache-retry-delay' must be 0 or greater.")
        }
    }
}
