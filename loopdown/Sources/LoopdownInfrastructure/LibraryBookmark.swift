//// LibraryBookmark.swift
// loopdown
//
// Created on 14/4/2026
//

import Foundation


// MARK: - Library dest path resolution

/// Returns `path` unchanged if its last path component already carries a `.bundle` extension;
/// otherwise appends `.bundle` and returns the result.
///
/// Examples:
///   "/Users/Shared/Logic Pro Library.bundle" → unchanged
///   "/Users/Shared/Logic Pro Library"        → "/Users/Shared/Logic Pro Library.bundle"
public func resolvedLibraryDestPath(_ path: String) -> String {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    guard url.pathExtension.lowercased() != "bundle" else { return path }
    return url.appendingPathExtension("bundle").path
}


// MARK: - Bookmark writer

/// Write a `.bookmark` file for `libraryDestURL` inside the bundle itself.
///
/// The bookmark filename is derived from the bundle name by replacing the `.bundle`
/// extension with `.bookmark`:
///   `Logic Pro Library.bundle` → `Logic Pro Library.bundle/Logic Pro Library.bookmark`
///
/// Ownership of the bookmark file is set to match the owner of the bundle, so that
/// a deploy run as root does not leave a root-owned file inside a user-owned bundle.
///
/// On a dry run the intended write is logged but no file is created.
/// Errors are logged and non-fatal; a bookmark failure does not abort the deploy.
public func writeBookmarkFile(
    libraryDestURL: URL,
    dryRun: Bool,
    logger: AppLogger
) {
    let stem         = libraryDestURL.deletingPathExtension().lastPathComponent
    let bookmarkName = stem + ".bookmark"
    let bookmarkURL  = libraryDestURL.appendingPathComponent(bookmarkName)

    if dryRun {
        logger.info("dry run: would write bookmark '\(bookmarkURL.path)'")
        return
    }

    do {
        // The bundle must exist before we can bookmark it.
        guard FileManager.default.fileExists(atPath: libraryDestURL.path) else {
            logger.error("Cannot write bookmark: '\(libraryDestURL.path)' does not exist.")
            return
        }

        let data = try libraryDestURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        try data.write(to: bookmarkURL, options: .atomicWrite)

        // Match the bookmark file's owner to the bundle's owner so that a deploy
        // run as root does not leave a root-owned file inside a user-owned bundle.
        let bundleAttrs = try FileManager.default.attributesOfItem(atPath: libraryDestURL.path)
        if let ownerID = bundleAttrs[.ownerAccountID] as? Int {
            try FileManager.default.setAttributes(
                [.ownerAccountID: ownerID],
                ofItemAtPath: bookmarkURL.path
            )
        }

        logger.debug("Bookmark written to '\(bookmarkURL.path)'")
    } catch {
        logger.error("Failed to write bookmark '\(bookmarkURL.path)': \(error)")
    }
}
