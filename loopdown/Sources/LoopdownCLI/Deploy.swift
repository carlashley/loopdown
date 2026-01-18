//// Deploy.swift
// loopdown
//
// Created on 18/1/2026
//
    

import ArgumentParser
import LoopdownInfrastructure
import LoopdownCore


// MARK: Deploy only arguments
struct ForceDeployOption: ParsableArguments {
    @Flag(name: [.short, .long], help: "Force install content packages regardless of existing install state.")
    var forceDeploy: Bool = false
}


// MARK: Deploy argument
struct Deploy: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install content for selected apps; requires root level privilege.",
        discussion: """
        Root privileges are required unless '-n/--dry-run' is specified.
        
        Downloaded content is temporarily staged in \(LoopdownConstants.Paths.defaultDest) and removed after successful install.
        
        If you need to download the content for use in a local mirror, use the 'download' command instead of 'deploy'.
        See 'loopdown download --help' for more information.
        """
    )

    @OptionGroup var dry: DryRunOption
    @OptionGroup var logging: LoggingOptions
    @OptionGroup var apps: AppOptions
    @OptionGroup var required: RequiredContentOption
    @OptionGroup var optional: OptionalContentOption
    @OptionGroup var force: ForceDeployOption
    @OptionGroup var servers: ServerOptions

    /// Fixed deploy destination. Not user configurable.
    var dest: String { LoopdownConstants.Paths.defaultDest }

    func validate() throws {
        // Enforce content selection
        try validateContentSelection(required: required.required, optional: optional.optional)
        
        // Validate root privileges when performing actual deploy run
        if !dry.dryRun && !PrivilegeCheck.isRoot {
            throw ValidationError("You must be root to use this command; re-run with sudo or use '-n/--dry-run'.")
        }
    }
    
    func run() throws {
        // Configure base (no output/files yet), then start run logging.
        CLILogging.configureBase(minLevel: logging.logLevel)
        // Start logging only once we know we're executing (not help/version/parse errors).
        let runLogURL = Log.startRunLogging(keepLatestCopy: true, keepMostRecentRuns: 5)
        Log.enableConsoleOutput()

        let logger = Log.category("Deploy")
        if let runLogURL {
            logger.notice("Log file: \(runLogURL.path)")
        }
        logger.debug("Debug test message")
        logger.info("Started deploy (dryRun=\(dry.dryRun))")
        logger.info("apps: \(apps.resolvedApps.map(\.rawValue).joined(separator: ", "))")
        if let cache = servers.cacheServer { logger.info("cacheServer: \(cache)") }
        if let mirror = servers.mirrorServer { logger.info("mirrorServer: \(mirror)") }
        logger.info("dest: \(dest)")

        // TODO: deploy logic
    }
    
    /* --- updated run func that handles staging directory creation when required
     func run() throws {
         Log.configureBase(minLevel: logging.logLevel, consoleEnabled: false)
         let runLogURL = Log.startRunLogging(keepLatestCopy: true, keepMostRecentRuns: 5)
         Log.enableConsoleOutput()

         let logger = Log.category("Deploy")
         if let runLogURL { logger.notice("Log file: \(runLogURL.path)") }

         logger.info("Started deploy (dryRun=\(dry.dryRun))")
         logger.info("apps: \(apps.resolvedApps.map(\.rawValue).joined(separator: ", "))")
         if let cache = servers.cacheServer { logger.info("cacheServer: \(cache)") }
         if let mirror = servers.mirrorServer { logger.info("mirrorServer: \(mirror)") }

         // Decide staging destination.
         // - dryRun: don't create anything; just use the conventional path for display/planning.
         // - real run: create a unique temp staging directory and guarantee cleanup.
         let staging: TemporaryDirectory?
         let signalCleanup: SignalCleanup?
         let effectiveDest: String

         if dry.dryRun {
             staging = nil
             signalCleanup = nil
             effectiveDest = DefaultPaths.dest
             logger.info("staging (dryRun): \(effectiveDest)")
         } else {
             let tmp = try TemporaryDirectory(prefix: "loopdown-staging-")
             staging = tmp
             effectiveDest = tmp.url.path
             logger.info("staging: \(effectiveDest)")

             let sc = SignalCleanup { tmp.cleanup() }
             sc.install()
             signalCleanup = sc
         }

         // Ensure the staging dir is cleaned up on normal exit as well.
         defer {
             staging?.cleanup()
             _ = signalCleanup // keep alive until function returns
         }

         do {
             _ = try processAudioContent(
                 mode: .deploy,
                 selectedApps: apps.resolvedApps,
                 includeMandatory: required.required,
                 includeOptional: optional.optional,
                 dest: effectiveDest,
                 dryRun: dry.dryRun,
                 logger: logger
             )
         } catch let e as ActionControllerError {
             throw ValidationError(e.description)
         }
     }

     */
}
