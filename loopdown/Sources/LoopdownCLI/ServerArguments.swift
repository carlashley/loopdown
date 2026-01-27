//// ServerArguments.swift
// loopdown
//
// Created on 18/1/2026
//
    

import ArgumentParser
import Foundation
import LoopdownCore


// MARK: - CacheServer arguments
enum CacheServer: ExpressibleByArgument, CustomStringConvertible, Equatable {
    case auto
    case url(URL)

    init?(argument: String) {
        if argument.lowercased() == "auto" {
            self = .auto
            return
        }
        guard let url = URL(string: argument), url.scheme != nil else { return nil }
        self = .url(url)
    }

    /// Convert CLI cache-server argument into the normalized caching server URL.
    /// - Returns: Normalized caching server URL, or nil if `.auto`.
    func normalizedURL(contentSourceHost: String? = nil) -> URL? {
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
    
    var description: String {
        switch self {
        case .auto: return "auto"
        case .url(let url): return url.absoluteString
        }
    }
}


// MARK: Mirroring Server arguments
enum MirrorServer: ExpressibleByArgument, CustomStringConvertible, Equatable {
    case url(URL)

    init?(argument: String) {
        guard let url = URL(string: argument), url.scheme != nil else { return nil }
        self = .url(url)
    }

    var url: URL {
        switch self {
        case .url(let u):
            return u
        }
    }
    
    var description: String {
        switch self {
        case .url(let url): return url.absoluteString
        }
    }
}
