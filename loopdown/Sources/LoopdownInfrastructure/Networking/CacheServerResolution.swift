//// CacheServerResolution.swift
// loopdown
//
// Created on 27/3/2026
//

import Foundation
import LoopdownCore


// MARK: - Cache server resolution

public enum CacheServerResolution {

    // MARK: Defaults

    /// Default maximum number of auto-discovery attempts (overridable via CLI).
    public static let defaultMaxAttempts: Int = 3

    /// Default delay in seconds between auto-discovery attempts (overridable via CLI).
    public static let defaultRetryDelay: UInt32 = 1

    /// Resolve the effective download base URL for downloads/deploys.
    ///
    /// Rules:
    ///   - `nil`   → nil (no cache server; caller uses `LoopdownConstants.Downloads.contentSourceBaseURL`)
    ///   - `.url`  → normalised caching server URL
    ///   - `.auto` → discover via `AssetCacheLocator`, retrying up to `maxAttempts` times
    ///               with `retryDelay` seconds between attempts → normalised URL if found
    ///   - `.auto` + none found after all attempts → `LoopdownConstants.Downloads.contentSourceBaseURL`
    public static func resolveCacheServerURL(
        _ cacheServer: CacheServer?,
        maxAttempts: Int = defaultMaxAttempts,
        retryDelay: UInt32 = defaultRetryDelay,
        logger: CoreLogger
    ) -> URL? {

        guard let cacheServer else { return nil }

        switch cacheServer {

        case .url:
            return cacheServer.normalizedURL(
                contentSourceHost: LoopdownConstants.Downloads.contentSourceBaseURL.host
            )

        case .auto:
            return resolveAuto(maxAttempts: maxAttempts, retryDelay: retryDelay, logger: logger)
        }
    }

    // MARK: - Auto discovery with retry

    private static func resolveAuto(maxAttempts: Int, retryDelay: UInt32, logger: CoreLogger) -> URL? {
        for attempt in 1...maxAttempts {
            if let discovered = AssetCacheLocator.extractCacheServerURL(debugLog: logger.debug) {
                logger.debug("Discovered caching server on attempt \(attempt)/\(maxAttempts): \(discovered.absoluteString)")
                return DownloadURLNormalizer.normalizeCachingServerURL(
                    discovered,
                    contentSource: LoopdownConstants.Downloads.contentSourceBaseURL.host
                )
            }

            if attempt < maxAttempts {
                logger.debug("No caching server found on attempt \(attempt)/\(maxAttempts); retrying in \(retryDelay)s")
                sleep(retryDelay)
            }
        }

        // Fallback: direct Apple content source (no normalisation)
        logger.debug("No caching server found after \(maxAttempts) attempts; using direct content source")
        return LoopdownConstants.Downloads.contentSourceBaseURL
    }
}
