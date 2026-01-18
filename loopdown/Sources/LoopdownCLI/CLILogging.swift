//// CLILogging.swift
// loopdown
//
// Created on 18/1/2026
//
    

import LoopdownInfrastructure
import LoopdownCore


// MARK: - CLI Logging configuration
enum CLILogging {

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

    /// Start per-run logging (files + console) and return a category logger.
    ///
    /// This bundles the common command boilerplate:
    /// - configure base
    /// - start run logging
    /// - enable console output
    /// - emit run log path
    static func startRun(
        category: String,
        minLevel: AppLogLevel,
        enableConsole: Bool = true,
        keepLatestLog: Bool = true,
        keepMostRecentRuns: Int = 5
    ) -> AppLogger {

        configureBase(minLevel: minLevel)

        let runLogURL = Log.startRunLogging(
            keepLatestCopy: keepLatestLog,
            keepMostRecentRuns: keepMostRecentRuns
        )

        if enableConsole {
            Log.enableConsoleOutput()
        }

        let logger = Log.category(category)
        if let runLogURL {
            logger.notice("Log file: \(runLogURL.path)")
        }

        return logger
    }
}
