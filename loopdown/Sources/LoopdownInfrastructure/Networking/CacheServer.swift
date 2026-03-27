//// CacheServer.swift
// loopdown
//
// Created on 27/3/2026
//
    

import Foundation
import LoopdownCore


// MARK: - CacheServer

/// Represents the cache server argument value: either auto-discovery or an explicit URL.
///
/// The `ExpressibleByArgument` conformance lives in `LoopdownCLI/CacheServer+ArgumentParser.swift`
/// so this type remains free of any ArgumentParser dependency.
@frozen public enum CacheServer: CustomStringConvertible, Equatable, Sendable {
    case auto
    case url(URL)

    /// Convert this cache-server value into the normalised caching server URL.
    /// Returns nil for `.auto` (auto-discovery is handled by `CacheServerResolution`).
    public func normalizedURL(contentSourceHost: String? = nil) -> URL? {
        switch self {
        case .auto:
            return nil
        case .url(let url):
            return DownloadURLNormalizer.normalizeCachingServerURL(
                url,
                contentSource: contentSourceHost
            )
        }
    }

    public var description: String {
        switch self {
        case .auto:        return "auto"
        case .url(let url): return url.absoluteString
        }
    }
}


// MARK: - MirrorServer

/// Represents a mirror server base URL for loopdown content downloads.
///
/// The `ExpressibleByArgument` conformance lives in `LoopdownCLI/CacheServer+ArgumentParser.swift`.
public struct MirrorServer: CustomStringConvertible, Equatable, Sendable {
    public let url: URL

    public init?(urlString: String) {
        guard let url = URL(string: urlString), url.scheme != nil else { return nil }
        self.url = url
    }

    public init(url: URL) {
        self.url = url
    }

    public var description: String { url.absoluteString }
}
