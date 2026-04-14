//// LibraryBookmark.swift
// loopdown
//
// Created on 14/4/2026
//

import Darwin
import Foundation
import LoopdownCore


// MARK: - Library dest path resolution

/// Returns the full path to the library bundle by joining `parentPath` with the
/// fixed bundle name (`LoopdownConstants.ModernApps.libraryBundleName`).
///
/// The caller provides the parent directory; the bundle name is always fixed.
///
/// Examples:
///   "/Users/Shared"  → "/Users/Shared/Logic Pro Library.bundle"
///   "/path/foo"      → "/path/foo/Logic Pro Library.bundle"
public func resolvedLibraryDestPath(_ parentPath: String) -> String {
    let parent = URL(fileURLWithPath: parentPath, isDirectory: true)
    return parent.appendingPathComponent(
        LoopdownConstants.ModernApps.libraryBundleName,
        isDirectory: true
    ).path
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
/// The `UF_HIDDEN` BSD flag is set on the bookmark file via `chflags(2)` so that it
/// is hidden from Finder and directory listings in the same way as `chflags hidden`.
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
        logger.debug("dry run: would write bookmark '\(bookmarkURL.path)'")
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

        // Set UF_HIDDEN via chflags(2) so the bookmark file is hidden from Finder
        // and directory listings, equivalent to `chflags hidden <file>`.
        bookmarkURL.path.withCString { cPath in
            _ = chflags(cPath, UInt32(UF_HIDDEN))
        }

        logger.debug("Bookmark written to '\(bookmarkURL.path)'")
    } catch {
        logger.error("Failed to write bookmark '\(bookmarkURL.path)': \(error)")
    }
}
