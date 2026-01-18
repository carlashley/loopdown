//// CommonArguments.swift
// loopdown
//
// Created on 18/1/2026
//
    

import ArgumentParser
import LoopdownInfrastructure
import LoopdownCore


// MARK: - Common arguments

struct AppOptions: ParsableArguments {
    @Option(
        name: [.short, .long],
        parsing: .upToNextOption,
        help: ArgumentHelp(
            "Install content for an app (default: all supported apps).\n",
            valueName: "app"
        )
    )
    var app: [ConcreteApp] = []

    var resolvedApps: [ConcreteApp] { app.isEmpty ? ConcreteApp.allCases : app }

}

struct DryRunOption: ParsableArguments {
    @Flag(name: [.customShort("n"), .long], help: "Perform a dry run.")
    var dryRun: Bool = false
}

struct LoggingOptions: ParsableArguments {
    @Option(name: .long)
    var logLevel: AppLogLevel = .info
}

struct RequiredContentOption: ParsableArguments {
    @Flag(name: [.short, .long], help: "Select required content.")
    var required: Bool = false
}

struct OptionalContentOption: ParsableArguments {
    @Flag(name: [.short, .long], help: "Select optional content.")
    var optional: Bool = false
}

struct ServerOptions: ParsableArguments {
    @Option(help: "Caching server to use; 'auto' or http://host:port")
    var cacheServer: CacheServer?

    @Option(help: "Mirror server base URL")
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

