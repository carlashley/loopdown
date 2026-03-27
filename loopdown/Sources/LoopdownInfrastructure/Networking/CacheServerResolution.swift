//// File.swift
// loopdown
//
// Created on 27/3/2026
//
    

import Foundation
import LoopdownCore


// MARK: - Cache server resolution

public enum CacheServerResolution {

    /// Resolve the effective download base URL for downloads/deploys.
    ///
    /// Rules:
    ///   - `nil`  → nil (no cache server; caller uses `LoopdownConstants.Downloads.contentSourceBaseURL`)
    ///   - `.url` → normalised caching server URL
    ///   - `.auto` → discover via `AssetCacheLocator` → normalised URL if found
    ///   - `.auto` + none found → `LoopdownConstants.Downloads.contentSourceBaseURL` (no normalisation)
    public static func resolveCacheServerURL(
        _ cacheServer: CacheServer?,
        logger: CoreLogger
    ) -> URL? {

        guard let cacheServer else { return nil }

        switch cacheServer {

        case .url:
            return cacheServer.normalizedURL(
                contentSourceHost: LoopdownConstants.Downloads.contentSourceBaseURL.host
            )

        case .auto:
            if let discovered = AssetCacheLocator.extractCacheServerURL(
                debugLog: logger.debug
            ) {
                logger.debug("Discovered caching server: \(discovered.absoluteString)")
                return DownloadURLNormalizer.normalizeCachingServerURL(
                    discovered,
                    contentSource: LoopdownConstants.Downloads.contentSourceBaseURL.host
                )
            }

            // Fallback: direct Apple content source (no normalisation)
            logger.debug("No caching server found (auto); using direct content source")
            return LoopdownConstants.Downloads.contentSourceBaseURL
        }
    }
}
