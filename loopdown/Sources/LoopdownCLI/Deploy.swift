//// Deploy.swift
// loopdown
//
// Created on 18/1/2026
//
    

import ArgumentParser
import LoopdownInfrastructure
import LoopdownCore
import LoopdownServices


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
        By default, content for all installed applications is processed. Provide the '-a/--app` argument to only target specific applications.
        
        Root privileges are required unless '-n/--dry-run' is specified.
        
        If you need to download the content for use in a local mirror, use the 'download' command instead of 'deploy'.
        See 'loopdown download --help' for more information.
        """
    )

    @OptionGroup var dry: DryRunOption
    @OptionGroup var quiet: QuietRunOption
    @OptionGroup var logging: LoggingOptions
    @OptionGroup var apps: AppOptions
    @OptionGroup var required: RequiredContentOption
    @OptionGroup var optional: OptionalContentOption
    @OptionGroup var force: ForceDeployOption
    @OptionGroup var servers: ServerOptions

    func validate() throws {
        // Enforce content selection
        try validateContentSelection(required: required.required, optional: optional.optional)
        
        // Validate root privileges when performing actual deploy run
        if !dry.dryRun && !PrivilegeCheck.isRoot {
            throw ValidationError("You must be root to use this command; re-run with sudo or use '-n/--dry-run'.")
        }
    }
    
    
    func run() throws {
        try CLIRunner.runLocked {
            do  {
                let logger = CLILogging.startRun(
                    category: "Deploy",
                    minLevel: logging.logLevel,
                    enableConsole: !quiet.quietRun
                )
                
                logger.info("Started deploy (dryRun=\(dry.dryRun))")
                logger.info("apps: \(apps.resolvedApps.map(\.rawValue).joined(separator: ", "))")
                
                if let cache = servers.cacheServer {
                    logger.info("cacheServer: \(cache)")
                }
                if let mirror = servers.mirrorServer {
                    logger.info("mirrorServer: \(mirror)")
                }
                
                // Decide staging destination.
                // - dryRun: do not create anything; just use the conventional path for display/planning.
                // - real run: create a unique temp staging directory and guarantee cleanup.
                let staging: TemporaryDirectory?
                let signalCleanup: SignalCleanup?
                
                if dry.dryRun {
                    staging = nil
                    signalCleanup = nil
                } else {
                    let tmp = try TemporaryDirectory(prefix: "loopdown-staging-")
                    staging = tmp
                    logger.info("staging: \(tmp.url.path)")
                    
                    let sc = SignalCleanup { tmp.cleanup() }
                    sc.install()
                    signalCleanup = sc
                }
                
                defer {
                    // Restore signals and cleanup on normal exit.
                    signalCleanup?.uninstall()
                    staging?.cleanup()
                }
                
                // Temporary: ensure scope doesn't end immediately
                logger.debug("Deploy logic not implemented yet...")
                // TODO: deploy logic
                // Use destPath as the staging directory for downloads/unpacks/etc.
                //
                // try DeployController.deploy(
                //     apps: apps.resolvedApps,
                //     required: required.required,
                //     optional: optional.optional,
                //     force: force.forceDeploy,
                //     cacheServer: servers.cacheServer,
                //     mirrorServer: servers.mirrorServer,
                //     stagingDir: destPath,
                //     dryRun: dry.dryRun,
                //     logger: logger
                // )
            }
        }
    }

}
