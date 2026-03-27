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
