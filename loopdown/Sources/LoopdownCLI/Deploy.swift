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
    var libraryDest: String = LoopdownConstants.ModernApps.defaultLibraryDestParent
}

struct AppGenerationOption: ParsableArguments {
    @Flag(name: .long, help: "Only deploy content for legacy apps (GarageBand; Logic Pro < 12; MainStage < 4).")
    var legacyOnly: Bool = false

    @Flag(name: .long, help: "Only deploy content for modern apps (Logic Pro >= 12; MainStage >= 4).")
    var modernOnly: Bool = false

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
            Only --dry-run, --cache-auto-retries/--cache-retry-delay, and/or --log-level may \
            be combined with --managed; all other flags are ignored and their values must be \
            set via the preferences domain.

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
        preferences domain (e.g. via MDM). Only '--dry-run' and cache discovery options \
        may be combined with '--managed'.

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
        if libraryDestOption.libraryDest != LoopdownConstants.ModernApps.defaultLibraryDestParent {
            throw ValidationError("'-b/--library-dest' cannot be used with '--managed'; set the 'libraryDest' key in the preferences domain instead.")
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
        try? FileManager.default.removeItem(
            atPath: "/Library/Application Support/com.github.carlashley.loopdown/run.trigger"
        )

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
            let libraryDestURL  = URL(
                fileURLWithPath: resolvedLibraryDestPath(libraryDestOption.libraryDest),
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
                verboseInstall: logging.logLevel <= AppLogLevel.debug,
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

            let effectiveLogLevel = logging.logLevel != .info ? logging.logLevel : prefs.logLevel

            let run = CLILogging.startRun(
                category: "Deploy",
                minLevel: effectiveLogLevel,
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

            let resolvedCacheServerURL = CacheServerResolution.resolveCacheServerURL(
                prefs.cacheServer,
                maxAttempts: cacheDiscovery.cacheAutoRetries,
                retryDelay: UInt32(cacheDiscovery.cacheRetryDelay),
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
                verboseInstall: effectiveLogLevel <= AppLogLevel.debug,
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
