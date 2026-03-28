//// Download.swift
// loopdown
//
// Created on 18/1/2026
//

import ArgumentParser
import LoopdownCore
import LoopdownServices
import LoopdownInfrastructure

// MARK: - Download only arguments
struct DestinationOption: ParsableArguments {
    @Option(
        name: [.short, .long],
        help: ArgumentHelp("Destination directory for downloading content.", valueName: "dir")
    )
    var dest: String = LoopdownConstants.Paths.defaultDest
}

// MARK: - Download command
struct Download: AsyncParsableCommand {
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
    @OptionGroup var quiet: QuietRunOption
    @OptionGroup var logging: LoggingOptions
    @OptionGroup var apps: AppOptions
    @OptionGroup var required: RequiredContentOption
    @OptionGroup var optional: OptionalContentOption
    @OptionGroup var destination: DestinationOption
    @OptionGroup var servers: ServerOptions
    @OptionGroup var cacheDiscovery: CacheAutoDiscoveryOptions
    @OptionGroup var signatureCheck: SkipSignatureCheckOption

    func validate() throws {
        try validateContentSelection(required: required.required, optional: optional.optional)
    }

    func run() async throws {
        try await ExecutionLock.withLockAsync {
            /// Emit a message to file sinks only — never console, regardless of console sink state.
            /// Used for run UID open/close lines that must not appear in terminal output.
            let run = CLILogging.startRun(
                category: "Download",
                minLevel: logging.logLevel,
                enableConsole: !quiet.quietRun
            )
            let logger = run.logger
            defer { run.emitRunEnd() }

            let resolvedCacheServerURL = CacheServerResolution.resolveCacheServerURL(
                servers.cacheServer,
                maxAttempts: cacheDiscovery.cacheAutoRetries,
                retryDelay: UInt32(cacheDiscovery.cacheRetryDelay),
                logger: logger
            )

            let mirrorServerURL = servers.mirrorServer?.url

            try await ContentCoordinator.run(
                mode: .download,
                selectedApps: apps.app,
                includeRequired: required.required,
                includeOptional: optional.optional,
                destDir: destination.dest,
                forceDeploy: false,
                skipSignatureCheck: signatureCheck.skipSignatureCheck,
                cacheServer: resolvedCacheServerURL,
                mirrorServer: mirrorServerURL,
                dryRun: dry.dryRun,
                logger: logger
            )
        }
    }
}
