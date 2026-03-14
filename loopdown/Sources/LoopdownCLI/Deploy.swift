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
struct Deploy: AsyncParsableCommand {
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
    @OptionGroup var signatureCheck: SkipSignatureCheckOption

    func validate() throws {
        try validateContentSelection(required: required.required, optional: optional.optional)

        if !dry.dryRun && !PrivilegeCheck.isRoot {
            throw ValidationError("You must be root to use this command; re-run with sudo or use '-n/--dry-run'.")
        }
    }

    func run() async throws {
        try await ExecutionLock.withLockAsync {
            let logger = CLILogging.startRun(
                category: "Deploy",
                minLevel: logging.logLevel,
                enableConsole: !quiet.quietRun
            )

            let resolvedCacheServerURL =
                CacheServerResolution.resolveCacheServerURL(
                    servers.cacheServer,
                    logger: logger
                )

            let mirrorServerURL = servers.mirrorServer?.url

            try await ContentCoordinator.run(
                mode: .deploy,
                selectedApps: apps.resolvedApps,
                includeRequired: required.required,
                includeOptional: optional.optional,
                destDir: LoopdownConstants.Paths.defaultDest,
                forceDeploy: force.forceDeploy,
                skipSignatureCheck: signatureCheck.skipSignatureCheck,
                cacheServer: resolvedCacheServerURL,
                mirrorServer: mirrorServerURL,
                dryRun: dry.dryRun,
                logger: logger
            )
        }
    }
}
