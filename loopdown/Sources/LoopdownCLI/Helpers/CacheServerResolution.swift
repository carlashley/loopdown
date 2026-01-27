//// CacheServerResolution.swift
// loopdown
//
// Created on 27/1/2026
//


import Foundation
import LoopdownCore
import LoopdownInfrastructure
import LoopdownServices

enum CacheServerResolution {
    /// Resolve the effective download base URL for downloads/deploys.
    ///
    /// Rules:
    /// - nil → nil (no cache server requested)
    /// - .url → normalized caching server URL
    /// - .auto → discover → normalized if found
    /// - .auto + none found → fallback to contentSourceBaseURL (NOT normalized)
    static func resolveCacheServerURL(
        _ cacheServer: CacheServer?,
        logger: CoreLogger
    ) -> URL? {

        guard let cacheServer else {
            return nil
        }

        switch cacheServer {

        case .url:
            // Delegate normalization to the enum
            return cacheServer.normalizedURL(
                contentSourceHost: LoopdownConstants.Downloads.contentSourceBaseURL.host
            )

        case .auto:
            // Try discovery
            if let discovered = AssetCacheLocator.extractCacheServerURL(
                debugLog: logger.debug
            ) {
                logger.debug("Discovered caching server: \(discovered.absoluteString)")

                // Normalize discovered cache server
                return DownloadURLNormalizer.normalizeCachingServerURL(
                    discovered,
                    contentSource: LoopdownConstants.Downloads.contentSourceBaseURL.host
                )
            }

            // Fallback: direct Apple content source (NO normalization)
            logger.debug("No caching server found (auto); using direct content source")
            return LoopdownConstants.Downloads.contentSourceBaseURL
        }
    }
}

