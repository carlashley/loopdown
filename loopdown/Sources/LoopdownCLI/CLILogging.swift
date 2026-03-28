//// CLILogging.swift
// loopdown
//
// Created on 18/1/2026
//

import Darwin
import Foundation
import LoopdownInfrastructure
import LoopdownCore


// MARK: - CLI Logging configuration
enum CLILogging {

    // MARK: Run context

    /// Returned by `startRun`; carries the logger and the run UID.
    /// Call `emitRunEnd()` after all work completes.
    struct RunContext {
        let logger: AppLogger
        let runUID: String

        /// Emit the closing run UID line — file log only, never console.
        func emitRunEnd() {
            logger.fileOnly("run end \(runUID)")
        }
    }

    // MARK: Baseline configuration

    /// Configure baseline logging (no file creation).
    ///
    /// Call this early only when you know you're about to do real work.
    static func configureBase(minLevel: AppLogLevel) {
        let subsystem = BuildInfo.identifier.isEmpty
            ? LoopdownConstants.Identifiers.defaultSubsystem
            : BuildInfo.identifier

        Log.configureBase(
            subsystem: subsystem,
            minLevel: minLevel,
            consoleEnabled: false
        )
    }

    // MARK: Start run

    /// Start per-run logging (files + console) and return a `RunContext`.
    ///
    /// This bundles the common command boilerplate:
    /// - configure base
    /// - start run logging
    /// - enable console output
    /// - emit startup diagnostics (version, macOS version, arguments)
    /// - emit opening run UID (file log only)
    static func startRun(
        category: String,
        minLevel: AppLogLevel,
        enableConsole: Bool = true,
        keepLatestLog: Bool = true,
        keepMostRecentRuns: Int = 5
    ) -> RunContext {

        configureBase(minLevel: minLevel)

        Log.startRunLogging(
            keepLatestCopy: keepLatestLog,
            keepMostRecentRuns: keepMostRecentRuns
        )

        if enableConsole {
            Log.enableConsoleOutput()
        }

        let logger = Log.category(category)
        let runUID = UUID().uuidString
        logger.fileOnly("run start \(runUID)")
        logStartupDiagnostics(logger)
        return RunContext(logger: logger, runUID: runUID)
    }

    // MARK: - Startup diagnostics

    /// Emit version, macOS version, and invocation arguments as the first debug
    /// lines of every run log, regardless of command or mode.
    private static func logStartupDiagnostics(_ logger: AppLogger) {
        // Full version line (marketing version + build number + configuration).
        logger.debug(BuildInfo.versionLine)

        // macOS version and kernel build number from ProcessInfo and sysctl.
        let osv = ProcessInfo.processInfo.operatingSystemVersion
        var buildNumber = "unknown"
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 {
                buildNumber = String(cString: buffer)
            }
        }
        logger.debug("macOS \(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion) (\(buildNumber))")

        // Full invocation as passed to the process, index 0 is the binary path.
        let args = ProcessInfo.processInfo.arguments
        logger.debug("invocation: \(args.joined(separator: " "))")
    }
}
