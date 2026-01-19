//// Download.swift
// loopdown
//
// Created on 18/1/2026
//
    
import Foundation
import ArgumentParser
//import LoopdownInfrastructure
import LoopdownCore
import LoopdownServices


// MARK: - Download only arguments
struct DestinationOption: ParsableArguments {
    @Option(name: [.short, .long], help: ArgumentHelp("Destination directory for downloading content.", valueName: "dir"))
    var dest: String = LoopdownConstants.Paths.defaultDest
}


// MARK: - Download argument
struct Download: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download content for selected apps.",
        discussion: """
        By default, content for all installed applications is processed. Provide the '-a/--app` argument to only target specific applications.
        Downloaded content is stored in \(LoopdownConstants.Paths.defaultDest); use '-d/--dest <dir>' to override. The directory will be created if it does not exist.
        
        Note: a local mirror must be served over HTTPS and the content must be uploaded to the server with the exact folder structure that this
        creates.
        """
    )

    @OptionGroup var dry: DryRunOption
    @OptionGroup var logging: LoggingOptions
    @OptionGroup var apps: AppOptions
    @OptionGroup var required: RequiredContentOption
    @OptionGroup var optional: OptionalContentOption
    @OptionGroup var destination: DestinationOption
    
    func validate() throws {
        // Enforce content selection
        try validateContentSelection(required: required.required, optional: optional.optional)
    }

    func run() throws {
        try CLIRunner.runLocked {
            let logger = CLILogging.startRun(
                category: "Download",
                minLevel: logging.logLevel
            )

            let installed = Array(InstalledApplicationResolver.resolveInstalled(logger: logger))
            let selectedApps = apps.resolvedApps

            let targetApps: [AudioApplication] =
                selectedApps.isEmpty
                ? installed
                : installed.filter { app in
                    guard let c = app.concreteApp else { return false }
                    return selectedApps.contains(c)
                }
            
            logger.info("Started download (dryRun=\(dry.dryRun))")
            logger.info("apps: \(apps.resolvedApps.map(\.rawValue).joined(separator: ", "))")
            logger.info("dest: \(destination.dest)")
            
            for app in targetApps {
                logger.info("-=== \(app.name) \(app.version) ===-")
                
                // Show raw package data (if exists0
                if let raw = app.packages {
                    logger.info("Packages (raw): \(raw.count)")
                } else {
                    logger.info("Packages (raw): nil (no app found or no Packages key")
                }
                
                logger.info("Packages (decoded): mandatory=\(app.mandatory.count), optional=\(app.optional.count)")
                
                // Respect CLI flags required/optional
                if required.required {
                    let reqdPackages = app.mandatory
                    let reqdTotal = reqdPackages.count
                    for (idx, pkg) in reqdPackages.enumerated(startingAt: 1) {
                        logger.info("    \(idx) of \(reqdTotal) [M] \(pkg.name) - \(pkg.downloadSize) download, \(pkg.installedSize) installed")
                    }
                }
                
                if optional.optional {
                    let optnPackages = app.optional
                    let optnTotal = optnPackages.count
                    for (idx, pkg) in optnPackages.enumerated(startingAt: 1) {
                        logger.info("    \(idx) of \(optnTotal) [O] \(pkg.name) - \(pkg.downloadSize) download, \(pkg.installedSize) installed")
                    }
                }
            }

            // TODO: download logic
        }
    }
}
