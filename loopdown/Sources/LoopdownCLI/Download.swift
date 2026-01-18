//// Download.swift
// loopdown
//
// Created on 18/1/2026
//
    

import ArgumentParser
import LoopdownInfrastructure
import LoopdownCore


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
        Downloaded content is stored in \(LoopdownConstants.Paths.defaultDest); this can be overridden with the '-d/--dest <dir>' argument.
        If the directory does not exist, it will automatically be created along with any missing parent directories.
        
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
        // Configure base (no output/files yet), then start run logging.
        CLILogging.configureBase(minLevel: logging.logLevel)
        // Start logging only once we know we're executing (not help/version/parse errors).
        let runLogURL = Log.startRunLogging(keepLatestCopy: true, keepMostRecentRuns: 5)
        Log.enableConsoleOutput()

        let logger = Log.category("Download")
        if let runLogURL {
            logger.notice("Log file: \(runLogURL.path)")
        }
        logger.debug("Debug test message")
        logger.info("Started download (dryRun=\(dry.dryRun))")
        logger.info("dryRun: \(dry.dryRun)")
        logger.info("apps: \(apps.resolvedApps.map(\.rawValue).joined(separator: ", "))")
        logger.info("dest: \(destination.dest)")

        // TODO: download logic
        
        /*
         Temp manual AudioApplication instance for sanity checking
        
        let apps = resolveInstalledApplications(logger: logger)
        
        for app in apps {
            print("=== \(app.name) \(app.version) ===")
            
            let contentPackages = app.optional
            
            for pkg in contentPackages {
                print("\(pkg.name) (\(pkg.downloadPath)) - \(pkg.downloadSize) downloaded")
            }
        }
        
        let resolved = Array(resolveInstalledApplications(logger: logger))

        print("Resolved apps: \(resolved.map(\.name).joined(separator: ", "))")
        print("Requested apps: \(apps.resolvedApps.map(\.rawValue).joined(separator: ", "))")
        print()

        for app in resolved {
            print("=== \(app.name) \(app.version) ===")
            print("Path: \(app.path.path)")

            // Show whether we even have raw package data
            if let raw = app.packages {
                print("Packages(raw): \(raw.count)")
            } else {
                print("Packages(raw): nil (no resource plist found or no Packages key)")
            }

            print("Packages(decoded): mandatory=\(app.mandatory.count), optional=\(app.optional.count)")

            // Respect CLI flags for what to print
            if required.required {
                for pkg in app.mandatory {
                    print("  [M] \(pkg.name) (\(pkg.downloadPath)) - \(pkg.downloadSize) downloaded")
                }
            }

            if optional.optional {
                for pkg in app.optional {
                    print("  [O] \(pkg.name) (\(pkg.downloadPath)) - \(pkg.downloadSize) downloaded")
                }
            }

            print()
        }
         */

    }
}
