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
    @Flag(name: [.short, .long], help: "Force install content packages regardless of existing install state.")
    var forceDeploy: Bool = false
}

struct ManagedOption: ParsableArguments {
    @Flag(
        name: .long,
        help: ArgumentHelp(
            "Run using managed preferences from the com.github.carlashley.loopdown preferences domain.",
            discussion: """
            When --managed is active, all deploy arguments are read from the \
            com.github.carlashley.loopdown CFPreferences domain. Only --dry-run \
            and --cache-auto-retries/--cache-retry-delay may be combined with \
            --managed; all other flags are ignored and their values must be set \
            via the preferences domain.

            Sane defaults are applied for any key absent from the domain:
              apps               all installed apps
              required           true (when both required and optional are absent)
              optional           false
              forceDeploy        false
              skipSignatureCheck false
              logLevel           info
              cacheServer        auto (when no server key is present)
              dryRun             false
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
    @OptionGroup var required: RequiredContentOption
    @OptionGroup var optional: OptionalContentOption
    @OptionGroup var force: ForceDeployOption
    @OptionGroup var servers: ServerOptions
    @OptionGroup var cacheDiscovery: CacheAutoDiscoveryOptions
    @OptionGroup var signatureCheck: SkipSignatureCheckOption
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
        // Under --managed, only --dry-run and cache discovery options are permitted.
        // Detect any explicitly-set flags that would conflict with the managed preferences domain.
        if !apps.app.isEmpty {
            throw ValidationError("'--app' cannot be used with '--managed'; set the 'apps' key in the preferences domain instead.")
        }
        if required.required {
            throw ValidationError("'--required' cannot be used with '--managed'; set the 'required' key in the preferences domain instead.")
        }
        if optional.optional {
            throw ValidationError("'--optional' cannot be used with '--managed'; set the 'optional' key in the preferences domain instead.")
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

        // Root check still applies unless --dry-run is set (either from CLI or from prefs,
        // but we can only read CLI here — prefs are read in run()).
        if !dry.dryRun && !PrivilegeCheck.isRoot {
            throw ValidationError("You must be root to use this command; re-run with sudo or use '-n/--dry-run'.")
        }
    }

    private func validateStandardMode() throws {
        try validateContentSelection(required: required.required, optional: optional.optional)

        if !dry.dryRun && !PrivilegeCheck.isRoot {
            throw ValidationError("You must be root to use this command; re-run with sudo or use '-n/--dry-run'.")
        }
    }

    // MARK: Run

    func run() async throws {
        // Consume the trigger file if the run was daemon-initiated.
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

            try await ContentCoordinator.run(
                mode: .deploy,
                selectedApps: apps.app,
                includeRequired: required.required,
                includeOptional: optional.optional,
                destDir: LoopdownConstants.Paths.defaultDest,
                forceDeploy: force.forceDeploy,
                skipSignatureCheck: signatureCheck.skipSignatureCheck,
                cacheServer: resolvedCacheServerURL,
                mirrorServer: mirrorServerURL,
                dryRun: dry.dryRun,
                verboseInstall: logging.logLevel <= AppLogLevel.debug,
                logger: logger
            )
        }
    }

    // MARK: - Managed run

    private func runManaged() async throws {
        try await ExecutionLock.withLockAsync {
            // Buffer plist diagnostics before the logger exists so we can replay them
            // through the single real logger after startRun. This avoids calling
            // startRun twice (which would create two log files, discarding the first).
            var prefsDebugLines: [String] = []
            let prefs = try ManagedPreferencesReader.read(debugLog: { prefsDebugLines.append($0) })

            // --dry-run CLI flag overrides the prefs value.
            let effectiveDryRun = dry.dryRun || prefs.dryRun

            // Under --managed the dry-run root check was already validated above for the
            // CLI --dry-run case. Re-check here for the prefs-driven dryRun=true case,
            // since validate() cannot read prefs at parse time.
            if !effectiveDryRun && !PrivilegeCheck.isRoot {
                throw ValidationError(
                    "You must be root to use this command; " +
                    "re-run with sudo, use '-n/--dry-run', or set 'dryRun = true' in the preferences domain."
                )
            }

            // CLI --log-level overrides the prefs value when explicitly provided.
            let effectiveLogLevel = logging.logLevel != .info ? logging.logLevel : prefs.logLevel

            /// Emit a message to file sinks only — never console, regardless of console sink state.
            /// Used for run UID open/close lines that must not appear in terminal output.
            let run = CLILogging.startRun(
                category: "Deploy",
                minLevel: effectiveLogLevel,
                enableConsole: !prefs.quietRun
            )
            let logger = run.logger
            defer { run.emitRunEnd() }

            // Replay buffered plist diagnostics through the real logger.
            prefsDebugLines.forEach { logger.debug($0) }

            logger.debug("--managed: reading from domain '\(ManagedPreferencesReader.domain)'")
            logger.debug("--managed: apps=\(prefs.apps.map { $0.rawValue })")
            logger.debug("--managed: required=\(prefs.required) optional=\(prefs.optional)")
            logger.debug("--managed: appPolicies=\(prefs.appPolicies.map { "\($0.app.rawValue)(r:\($0.required) o:\($0.optional))" })")
            logger.debug("--managed: forceDeploy=\(prefs.forceDeploy) skipSignatureCheck=\(prefs.skipSignatureCheck)")
            logger.debug("--managed: dryRun=\(effectiveDryRun) (prefs=\(prefs.dryRun) cli=\(dry.dryRun))")

            let resolvedCacheServerURL = CacheServerResolution.resolveCacheServerURL(
                prefs.cacheServer,
                maxAttempts: cacheDiscovery.cacheAutoRetries,
                retryDelay: UInt32(cacheDiscovery.cacheRetryDelay),
                logger: logger
            )

            let mirrorServerURL = prefs.mirrorServer?.url

            try await ContentCoordinator.run(
                mode: .deploy,
                selectedApps: prefs.apps,
                includeRequired: prefs.required,
                includeOptional: prefs.optional,
                appPolicies: prefs.appPolicies,
                destDir: LoopdownConstants.Paths.defaultDest,
                forceDeploy: prefs.forceDeploy,
                skipSignatureCheck: prefs.skipSignatureCheck,
                cacheServer: resolvedCacheServerURL,
                mirrorServer: mirrorServerURL,
                dryRun: effectiveDryRun,
                verboseInstall: effectiveLogLevel <= AppLogLevel.debug,
                logger: logger
            )
        }
    }
}
