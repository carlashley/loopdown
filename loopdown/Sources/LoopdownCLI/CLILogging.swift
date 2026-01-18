//// CLILogging.swift
// loopdown
//
// Created on 18/1/2026
//
    

import LoopdownInfrastructure
import LoopdownCore


// MARK: - CLI Logging configuration
enum CLILogging {
    /// Configure base logging for a command invocation.
    ///
    /// This should be called at the start of `run()` for commands that
    /// actually execute work (not for help/version).
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
}
