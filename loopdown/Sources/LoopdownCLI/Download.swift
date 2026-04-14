//// Download.swift
// loopdown
//
// Created on 18/1/2026
//

import Foundation
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
    @OptionGroup var essential: EssentialContentOption
    @OptionGroup var core: CoreContentOption
    @OptionGroup var optional: OptionalContentOption
    @OptionGroup var destination: DestinationOption
    @OptionGroup var signatureCheck: SkipSignatureCheckOption

    func validate() throws {
        try validateContentSelection(
            essential: essential.essential,
            core: core.core,
            optional: optional.optional
        )
    }

    func run() async throws {
        try await ExecutionLock.withLockAsync {
            let run = CLILogging.startRun(
                category: "Download",
                minLevel: logging.logLevel,
                enableConsole: !quiet.quietRun
            )
            let logger = run.logger
            defer { run.emitRunEnd() }

            // Download always fetches directly from Apple CDN.
            // Cache server and mirror server are deploy-only options.
            let libraryDestURL = URL(
                fileURLWithPath: LoopdownConstants.ModernApps.defaultLibraryDestPath,
                isDirectory: true
            )

            try await ContentCoordinator.run(
                mode: .download,
                selectedApps: apps.app,
                includeEssential: essential.essential,
                includeCore: core.core,
                includeOptional: optional.optional,
                libraryDestURL: libraryDestURL,
                destDir: destination.dest,
                forceDeploy: false,
                skipSignatureCheck: signatureCheck.skipSignatureCheck,
                cacheServer: nil,
                mirrorServer: nil,
                dryRun: dry.dryRun,
                logger: logger
            )
        }
    }
}
