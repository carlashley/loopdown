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
    /// Resolve installed audio applications that loopdown can process
    public static func resolveInstalled(
        logger: CoreLogger = NullLogger()
    ) -> [AudioApplication] {

        guard let installedApps = SystemProfiler.run(.applications, debugLog: logger.debug)
        else {
            return []
        }

        return installedApps.compactMap { app -> AudioApplication? in
            guard let rawName = app["_name"] as? String else { return nil }

            let normalized = LoopdownConstants.Applications.normalizeName(rawName)
            guard LoopdownConstants.Applications.realNames.contains(normalized) else { return nil }

            let version = app["version"] as? String ?? ""
            let pathString = app["path"] as? String ?? ""
            let lastModified = app["lastModified"] as? String ?? ""

            guard !pathString.isEmpty else {
                logger.debug("Skipping '\(rawName)': missing path")
                return nil
            }

            let url = URL(fileURLWithPath: pathString, isDirectory: true)

            do {
                return try AudioApplication(
                    name: rawName,
                    version: version,
                    path: url,
                    lastModifiedISO8601UTC: lastModified,
                    logger: logger
                )
            } catch {
                logger.debug("Skipping '\(rawName)': invalid lastModified '\(lastModified)'")
                return nil
            }
        }
    }
}


/*
 usage:
 In CLI:
 let installed = InstalledApplicationResolver.resolveInstalled(logger: logger)
 Then filter based on -a/--app:
 let selectedApps = apps.resolvedApps

 let targetApps = selectedApps.isEmpty
     ? installed
     : installed.filter { selectedApps.contains($0.concreteApp) }
 This keeps selection policy in CLI and discovery in Services.
 */
