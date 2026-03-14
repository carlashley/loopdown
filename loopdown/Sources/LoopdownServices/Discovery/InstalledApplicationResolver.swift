//// InstalledApplicationResolver.swift
// loopdown
//
// Created on 18/1/2026
//

import Foundation
import LoopdownCore
import LoopdownInfrastructure


// MARK: - Installed application resolver
public enum InstalledApplicationResolver {
    /// Resolve installed audio applications that loopdown can process.
    public static func resolveInstalled(
        logger: CoreLogger = NullLogger()
    ) -> AnySequence<AudioApplication> {

        guard let installedApps = SystemProfiler.run(.applications, debugLog: logger.debug) else {
            return AnySequence([])
        }

        return AnySequence(
            installedApps.lazy.compactMap { app -> AudioApplication? in
                // system_profiler keys we care about
                guard let rawName = app["_name"] as? String else { return nil }

                let normalized = LoopdownConstants.Applications.normalizeName(rawName)
                guard LoopdownConstants.Applications.realNames.contains(normalized) else { return nil }

                let version = app["version"] as? String ?? ""
                let pathString = app["path"] as? String ?? ""

                guard !pathString.isEmpty else {
                    logger.debug("Skipping '\(rawName)': missing path")
                    return nil
                }

                let url = URL(fileURLWithPath: pathString, isDirectory: true)

                return AudioApplication(
                    name: rawName,
                    version: version,
                    path: url,
                    logger: logger
                )
            }
        )
    }
}
