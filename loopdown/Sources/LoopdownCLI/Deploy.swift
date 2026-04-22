//// Deploy.swift
// loopdown
//
// Created on 18/1/2026
//

import ArgumentParser
import Foundation
import LoopdownInfrastructure
import LoopdownCore
import LoopdownServices


// MARK: - Deploy-only arguments

struct ForceDeployOption: ParsableArguments {
    @Flag(name: [.customShort("f"), .customLong("force")], help: "Force install content packages regardless of existing install state.")
    var forceDeploy: Bool = false
}

struct LibraryDestOption: ParsableArguments {
    @Option(
        name: [.customShort("b"), .customLong("library-dest")],
        help: ArgumentHelp(
            "Parent directory for the \(LoopdownConstants.ModernApps.libraryBundleName) bundle.",
            valueName: "dir"
        )
    )
    var libraryDest: String? = nil

    /// True only when the flag was explicitly provided on the command line.
    var wasSet: Bool { libraryDest != nil }

    /// Resolved value — explicit flag value, or the compiled-in default.
    var resolvedPath: String { libraryDest ?? LoopdownConstants.ModernApps.defaultLibraryDestParent }
}

struct AppGenerationOption: ParsableArguments {
    @Flag(name: .long, help: "Only deploy content for legacy apps (GarageBand; Logic Pro < 12; MainStage < 4).")
    var legacyOnly: Bool = false

    @Flag(name: .long, help: "Only deploy content for modern apps (Logic Pro >= 12; MainStage >= 4).")
    var modernOnly: Bool = false

    /// True if either flag was explicitly passed on the command line.
    var wasSet: Bool { legacyOnly || modernOnly }

    mutating func validate() throws {
        if legacyOnly && modernOnly {
            throw ValidationError("'--legacy-only' and '--modern-only' are mutually exclusive.")
        }
    }

    var appGeneration: AppGeneration {
        if legacyOnly { return .legacyOnly }
        if modernOnly { return .modernOnly }
        return .any
    }
}

struct ManagedOption: ParsableArguments {
    @Flag(
        name: .long,
        help: ArgumentHelp(
            "Run using managed preferences from the com.github.carlashley.loopdown preferences domain.",
            discussion: """
            Only --dry-run and/or --log-level may be combined with --managed; \
            all other flags are ignored and their values must be set via the preferences domain.

            Sane defaults are applied for any key absent from the domain:
              apps               all installed apps
              essential          true (when essential, core, and optional are all absent)
              core               true (when essential, core, and optional are all absent)
              optional           false
              forceDeploy        false
              skipSignatureCheck false
              logLevel           info
              cacheServer        auto (when no server key is present)
              dryRun             false
              libraryDest        \(LoopdownConstants.ModernApps.defaultLibraryDestParent)
            """
        )
    )
    var managed: Bool = false
}


// MARK: - Deploy command

struct Deploy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install content for selected apps; requires root level privilege.",
        discussion: """
        By default, content for all installed applications is processed. Provide the \
        '-a/--app' argument to only target specific applications.

        Root privileges are required unless '-n/--dry-run' is specified.

        Use '--managed' to drive all arguments from the com.github.carlashley.loopdown \
        preferences domain (e.g. via MDM). Only '--dry-run' and '--log-level' may be combined with '--managed'.

        If you need to download content for a local mirror, use the 'download' command instead.
        See 'loopdown download --help' for more information.
        """
    )

    @OptionGroup var dry: DryRunOption
    @OptionGroup var quiet: QuietRunOption
    @OptionGroup var logging: LoggingOptions
    @OptionGroup var apps: AppOptions
    @OptionGroup var libraryDestOption: LibraryDestOption
    @OptionGroup var essential: EssentialContentOption
    @OptionGroup var core: CoreContentOption
    @OptionGroup var optional: OptionalContentOption
    @OptionGroup var force: ForceDeployOption
    @OptionGroup var servers: ServerOptions
    @OptionGroup var cacheDiscovery: CacheAutoDiscoveryOptions
    @OptionGroup var signatureCheck: SkipSignatureCheckOption
    @OptionGroup var appGeneration: AppGenerationOption
    @OptionGroup var managedOption: ManagedOption
    @OptionGroup var retryOptions: DownloadRetryOptions
    @OptionGroup var bandwidthOptions: DownloadBandwidthOptions

    // MARK: Validation

    func validate() throws {
        if managedOption.managed {
            try validateManagedMode()
        } else {
            try validateStandardMode()
        }
    }

    private func validateManagedMode() throws {
        if !apps.app.isEmpty {
            throw ValidationError("'--app' cannot be used with '--managed'; set the 'apps' key in the preferences domain instead.")
        }
        if essential.essential {
            throw ValidationError("'-e/--essential' cannot be used with '--managed'; set the 'essential' key in the preferences domain instead.")
        }
        if core.core {
            throw ValidationError("'-r/--core' cannot be used with '--managed'; set the 'core' key in the preferences domain instead.")
        }
        if optional.optional {
            throw ValidationError("'-o/--optional' cannot be used with '--managed'; set the 'optional' key in the preferences domain instead.")
        }
        if force.forceDeploy {
            throw ValidationError("'--force-deploy' cannot be used with '--managed'; set the 'forceDeploy' key in the preferences domain instead.")
        }
        if servers.cacheServer != nil {
            throw ValidationError("'--cache-server' cannot be used with '--managed'; set the 'cacheServer' key in the preferences domain instead.")
        }
        if servers.mirrorServer != nil {
            throw ValidationError("'--mirror-server' cannot be used with '--managed'; set the 'mirrorServer' key in the preferences domain instead.")
        }
        if signatureCheck.skipSignatureCheck {
            throw ValidationError("'--skip-signature-check' cannot be used with '--managed'; set the 'skipSignatureCheck' key in the preferences domain instead.")
        }
        if quiet.quietRun {
            throw ValidationError("'--quiet' cannot be used with '--managed'; set the 'quietRun' key in the preferences domain instead.")
        }
        if libraryDestOption.wasSet {
            throw ValidationError("'-b/--library-dest' cannot be used with '--managed'; set the 'libraryDest' key in the preferences domain instead.")
        }
        if cacheDiscovery.cacheAutoRetries != nil {
            throw ValidationError("'--cache-auto-retries' cannot be used with '--managed'.")
        }
        if cacheDiscovery.cacheRetryDelay != nil {
            throw ValidationError("'--cache-retry-delay' cannot be used with '--managed'.")
        }
        if appGeneration.wasSet {
            throw ValidationError("'--legacy-only' and '--modern-only' cannot be used with '--managed'.")
        }
        if retryOptions.maxRetries != nil {
            throw ValidationError("'--max-retries' cannot be used with '--managed'; set the 'maxRetries' key in the preferences domain instead.")
        }
        if retryOptions.backoffSleep != nil {
            throw ValidationError("'--backoff-sleep' cannot be used with '--managed'; set the 'retryDelay' key in the preferences domain instead.")
        }
        if bandwidthOptions.minimumBandwidth != nil {
            throw ValidationError("'--minimum-bandwidth' cannot be used with '--managed'; set the 'minimumBandwidth' key in the preferences domain instead.")
        }
        if bandwidthOptions.bandwidthTimeout != nil {
            throw ValidationError("'--bandwidth-timeout' cannot be used with '--managed'; set the 'bandwidthWindow' key in the preferences domain instead.")
        }
        if bandwidthOptions.abortAfter != nil {
            throw ValidationError("'--abort-after' cannot be used with '--managed'; set the 'abortAfter' key in the preferences domain instead.")
        }

        if !dry.dryRun && !PrivilegeCheck.isRoot {
            throw ValidationError("You must be root to use this command; re-run with sudo or use '-n/--dry-run'.")
        }
    }

    private func validateStandardMode() throws {
        try validateContentSelection(
            essential: essential.essential,
            core: core.core,
            optional: optional.optional
        )

        if !dry.dryRun && !PrivilegeCheck.isRoot {
            throw ValidationError("You must be root to use this command; re-run with sudo or use '-n/--dry-run'.")
        }
    }

    // MARK: Run

    func run() async throws {
        if managedOption.managed {
            try await runManaged()
        } else {
            try await runStandard()
        }
    }

    // MARK: - Standard (non-managed) run

    private func runStandard() async throws {
        try await ExecutionLock.withLockAsync {
            let run = CLILogging.startRun(
                category: "Deploy",
                minLevel: logging.logLevel,
                isActualDeploy: !dry.dryRun,
                enableConsole: !quiet.quietRun
            )
            let logger = run.logger
            defer { run.emitRunEnd() }

            let resolvedCacheServerURL = CacheServerResolution.resolveCacheServerURL(
                servers.cacheServer,
                maxAttempts: cacheDiscovery.effectiveCacheAutoRetries,
                retryDelay: UInt32(cacheDiscovery.effectiveCacheRetryDelay),
                logger: logger
            )

            let mirrorServerURL = servers.mirrorServer?.url
            let libraryDestURL  = URL(
                fileURLWithPath: resolvedLibraryDestPath(libraryDestOption.resolvedPath),
                isDirectory: true
            )

            let modernContentDeployed = try await ContentCoordinator.run(
                mode: .deploy,
                selectedApps: apps.app,
                includeEssential: essential.essential,
                includeCore: core.core,
                includeOptional: optional.optional,
                appGeneration: appGeneration.appGeneration,
                libraryDestURL: libraryDestURL,
                destDir: LoopdownConstants.Paths.defaultDest,
                forceDeploy: force.forceDeploy,
                skipSignatureCheck: signatureCheck.skipSignatureCheck,
                cacheServer: resolvedCacheServerURL,
                mirrorServer: mirrorServerURL,
                dryRun: dry.dryRun,
                maxRetries: retryOptions.effectiveMaxRetries,
                retryDelay: retryOptions.effectiveBackoffSleep,
                minimumBandwidth: bandwidthOptions.minimumBandwidthBytesPerSec,
                bandwidthWindow: bandwidthOptions.effectiveBandwidthTimeout,
                bandwidthAbortAfter: bandwidthOptions.effectiveBandwidthAbortAfter,
                verboseInstall: logging.isVerbose,
                logger: logger
            )

            if modernContentDeployed {
                writeBookmarkFile(
                    libraryDestURL: libraryDestURL,
                    dryRun: dry.dryRun,
                    logger: logger
                )
            }
        }
    }

    // MARK: - Managed run

    private func runManaged() async throws {
        try await ExecutionLock.withLockAsync {
            var prefsDebugLines: [String] = []
            let prefs = try ManagedPreferencesReader.read(debugLog: { prefsDebugLines.append($0) })

            let effectiveDryRun = dry.dryRun || prefs.dryRun

            if !effectiveDryRun && !PrivilegeCheck.isRoot {
                throw ValidationError(
                    "You must be root to use this command; " +
                    "re-run with sudo, use '-n/--dry-run', or set 'dryRun = true' in the preferences domain."
                )
            }

            // Log level can be managed/applied via CLI, so get the effective level and use that
            let effectiveLogLevel = logging.logLevel != .info ? logging.logLevel : prefs.logLevel
            let isVerboseInstall = effectiveLogLevel <= .debug

            let run = CLILogging.startRun(
                category: "Deploy",
                minLevel: effectiveLogLevel,
                isActualDeploy: !effectiveDryRun,
                enableConsole: !prefs.quietRun
            )
            let logger = run.logger
            defer { run.emitRunEnd() }

            prefsDebugLines.forEach { logger.debug($0) }

            logger.debug("--managed: reading from domain '\(ManagedPreferencesReader.domain)'")
            logger.debug("--managed: apps=\(prefs.apps.map { $0.rawValue })")
            logger.debug("--managed: essential=\(prefs.essential) core=\(prefs.core) optional=\(prefs.optional)")
            logger.debug("--managed: appPolicies=\(prefs.appPolicies.map { "\($0.app.rawValue)(e:\($0.essential) c:\($0.core) o:\($0.optional))" })")
            logger.debug("--managed: forceDeploy=\(prefs.forceDeploy) skipSignatureCheck=\(prefs.skipSignatureCheck)")
            logger.debug("--managed: dryRun=\(effectiveDryRun) (prefs=\(prefs.dryRun) cli=\(dry.dryRun))")
            logger.debug("--managed: libraryDest=\(prefs.libraryDest)")
            logger.debug("--managed: maxRetries=\(prefs.maxRetries) retryDelay=\(prefs.retryDelay)")
            logger.debug("--managed: minimumBandwidth=\(prefs.minimumBandwidth.map { "\($0 / 1024)KB/s" } ?? "none") bandwidthWindow=\(prefs.bandwidthWindow) abortAfter=\(prefs.abortAfter)")

            // maxAttempts and retryDelay are not directly managed by profiles/DDM
            let resolvedCacheServerURL = CacheServerResolution.resolveCacheServerURL(
                prefs.cacheServer,
                maxAttempts: cacheDiscovery.effectiveCacheAutoRetries,
                retryDelay: UInt32(cacheDiscovery.effectiveCacheRetryDelay),
                logger: logger
            )

            let mirrorServerURL = prefs.mirrorServer?.url
            let libraryDestURL  = URL(
                fileURLWithPath: resolvedLibraryDestPath(prefs.libraryDest),
                isDirectory: true
            )

            let modernContentDeployed = try await ContentCoordinator.run(
                mode: .deploy,
                selectedApps: prefs.apps,
                includeEssential: prefs.essential,
                includeCore: prefs.core,
                includeOptional: prefs.optional,
                appPolicies: prefs.appPolicies,
                appGeneration: .any,
                libraryDestURL: libraryDestURL,
                destDir: LoopdownConstants.Paths.defaultDest,
                forceDeploy: prefs.forceDeploy,
                skipSignatureCheck: prefs.skipSignatureCheck,
                cacheServer: resolvedCacheServerURL,
                mirrorServer: mirrorServerURL,
                dryRun: effectiveDryRun,
                maxRetries: prefs.maxRetries,
                retryDelay: prefs.retryDelay,
                minimumBandwidth: prefs.minimumBandwidth,
                bandwidthWindow: prefs.bandwidthWindow,
                // abortAfter only applies when minimumBandwidth is set; no computed property on ManagedPreferences.
                bandwidthAbortAfter: prefs.minimumBandwidth != nil ? prefs.abortAfter : nil,
                verboseInstall: isVerboseInstall,
                logger: logger
            )

            if modernContentDeployed {
                writeBookmarkFile(
                    libraryDestURL: libraryDestURL,
                    dryRun: effectiveDryRun,
                    logger: logger
                )
            }
        }
    }
}
