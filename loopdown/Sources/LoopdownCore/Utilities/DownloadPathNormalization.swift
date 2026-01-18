//// DownloadPathNormalization.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation


// MARK: - Cache Server URL normalization
public enum DownloadURLNormalizer {
    /// Normalize a caching server URL for package downloads.
    ///
    /// - Parameters:
    ///   - url: The caching server base URL.
    ///   - contentSource: Optional content source host override.
    /// - Returns: Normalized URL suitable for package downloads.
    public static func normalizeCachingServerURL(
        _ url: URL,
        contentSource: String? = nil
    ) -> URL? {

        let sourceHost = contentSource ?? LoopdownConstants.Downloads.contentSourceBaseURL.host

        guard let sourceHost else {
            return nil
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "http"

        // Normalize path (mirrors posixpath.normpath)
        let normalizedPath = (components?.path as NSString?)?
            .standardizingPath ?? ""

        if normalizedPath == "." || normalizedPath == "/" {
            components?.path = ""
        } else {
            components?.path = normalizedPath
        }

        components?.queryItems = [
            URLQueryItem(name: "source", value: sourceHost),
            URLQueryItem(name: "sourceScheme", value: "https")
        ]

        return components?.url
    }
}


// MARK: - Package Path normalization
public enum PackagePathNormalizer {
    /// Normalize a package download path.
    ///
    /// - Parameter name: Raw package download name.
    /// - Returns: Normalized relative package path.
    public static func normalizePackageDownloadPath(
        _ name: String
    ) -> String {

        let basename = (name as NSString).lastPathComponent

        if name.contains(LoopdownConstants.Downloads.ContentPaths.path2013) {
            return "\(LoopdownConstants.Downloads.ContentPaths.path2013)/\(basename)"
        }

        return "\(LoopdownConstants.Downloads.ContentPaths.path2016)/\(basename)"
    }
}
