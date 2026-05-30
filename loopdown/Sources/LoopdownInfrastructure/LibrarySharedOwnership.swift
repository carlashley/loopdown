//// LibrarySharedOwnership.swift
// loopdown
//
// Created on 30/5/2026
//

import Darwin
import Foundation
import LoopdownCore


// MARK: - Shared-location ownership enforcement

/// Returns `true` if `libraryDestURL`'s parent directory is the default shared
/// location (`/Users/Shared`), comparing standardised filesystem paths so that a
/// path supplied explicitly via `-b/--library-dest` is treated the same as the
/// compiled-in default.
///
/// The library bundle's parent is the directory the user supplies; the bundle
/// name itself (`Logic Pro Library.bundle`) is fixed, so the parent of
/// `libraryDestURL` is compared against `defaultLibraryDestParent`.
public func libraryDestIsDefaultShared(_ libraryDestURL: URL) -> Bool {
    let parent = libraryDestURL.deletingLastPathComponent().standardizedFileURL.path
    let shared = URL(fileURLWithPath: LoopdownConstants.ModernApps.defaultLibraryDestParent,
                     isDirectory: true).standardizedFileURL.path
    return parent == shared
}


/// Recursively set ownership of the library bundle at `libraryDestURL` to
/// `root:wheel`. Permission bits are left untouched — only the owning user and
/// group are changed.
///
/// This is applied as the final step of a deploy run, after the bookmark file is
/// written, but ONLY when the library was deployed into the default shared
/// location (`/Users/Shared`). The shared directory is world-writable, so the
/// bundle and everything inside it is owned by `root:wheel` to ensure it remains
/// readable by all users while being modifiable only by root. When the library is
/// deployed elsewhere (an explicit non-shared `-b/--library-dest`), ownership is
/// left as the extracting process created it and this function is not called.
///
/// The caller is responsible for gating on `libraryDestIsDefaultShared` and on
/// the run not being a dry run; this function also no-ops on a dry run as a
/// defensive measure, logging the intent without changing anything.
///
/// Ownership changes require root privilege. A deploy that reaches this point on a
/// real (non-dry) run has already passed the root check in the command layer, so
/// `chown(2)` is expected to succeed; any failure is logged and treated as
/// non-fatal so that a late ownership error does not discard a completed deploy.
///
/// - Parameters:
///   - libraryDestURL: File URL of the `Logic Pro Library.bundle` directory.
///   - dryRun: When `true`, the intended change is logged and nothing is applied.
///   - logger: Logger for debug and error output.
public func enforceSharedLibraryOwnership(
    libraryDestURL: URL,
    dryRun: Bool,
    logger: AppLogger
) {
    if dryRun {
        logger.fileOnly("dry run: would set '\(libraryDestURL.path)' to root:wheel recursively")
        return
    }

    guard FileManager.default.fileExists(atPath: libraryDestURL.path) else {
        logger.error("Cannot set ownership: '\(libraryDestURL.path)' does not exist.")
        return
    }

    // Resolve root/wheel by name, falling back to the well-known ids 0/0 if the
    // lookup fails for any reason. On macOS these always resolve, but the fallback
    // keeps the behaviour correct rather than aborting the ownership pass.
    let rootUID = userID(forName: "root") ?? 0
    let wheelGID = groupID(forName: "wheel") ?? 0

    logger.fileOnly("Setting ownership of '\(libraryDestURL.path)' to root:wheel (uid=\(rootUID) gid=\(wheelGID)) recursively")

    var failures = 0
    var changed  = 0

    // chown the bundle directory itself first, then everything beneath it.
    if !chownPath(libraryDestURL.path, uid: rootUID, gid: wheelGID, logger: logger) {
        failures += 1
    } else {
        changed += 1
    }

    if let enumerator = FileManager.default.enumerator(
        at: libraryDestURL,
        includingPropertiesForKeys: nil,
        options: []   // include hidden files (e.g. the .bookmark)
    ) {
        for case let child as URL in enumerator {
            if chownPath(child.path, uid: rootUID, gid: wheelGID, logger: logger) {
                changed += 1
            } else {
                failures += 1
            }
        }
    } else {
        logger.error("Could not enumerate '\(libraryDestURL.path)' to set ownership.")
    }

    if failures == 0 {
        logger.fileOnly("Ownership set to root:wheel on \(changed) item(s) under '\(libraryDestURL.lastPathComponent)'")
    } else {
        logger.error("Set ownership on \(changed) item(s); \(failures) failure(s) under '\(libraryDestURL.lastPathComponent)'")
    }
}


// MARK: - Private helpers

/// Set ownership of a single path via `lchown(2)`, which does not follow symlinks,
/// so a symlink in the tree has its own ownership changed rather than its target's.
/// Returns `true` on success. Logs and returns `false` on failure.
private func chownPath(_ path: String, uid: uid_t, gid: gid_t, logger: AppLogger) -> Bool {
    let rc = path.withCString { lchown($0, uid, gid) }
    if rc != 0 {
        let err = String(cString: strerror(errno))
        logger.fileOnly("chown failed for '\(path)': \(err)")
        return false
    }
    return true
}

/// Resolve a user name to its uid via `getpwnam(3)`. Returns `nil` if not found.
private func userID(forName name: String) -> uid_t? {
    guard let pw = getpwnam(name) else { return nil }
    return pw.pointee.pw_uid
}

/// Resolve a group name to its gid via `getgrnam(3)`. Returns `nil` if not found.
private func groupID(forName name: String) -> gid_t? {
    guard let gr = getgrnam(name) else { return nil }
    return gr.pointee.gr_gid
}
