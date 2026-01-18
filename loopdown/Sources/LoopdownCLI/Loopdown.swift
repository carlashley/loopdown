//// Loopdown.swift
// loopdown
//
// Created on 18/1/2026
//
    

import ArgumentParser
import LoopdownCore

@main
struct Loopdown: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "loopdown",
        abstract: "Manage additional content for Apple's audio applications, GarageBand, Logic Pro, and/or MainStage.",
        discussion: """
        These arguments are supported in both 'deploy' and 'download' commands:
          -n, --dry-run     Perform a dry run.
          -a, --app <app>   Install content for an app (default: all supported apps).
          -r, --required    Select required content.
          -o, --optional    Select optional content.

        COMMENTS:
          -r, --required / -o, --optional one or both are required.
          -a, --app is not required; omitting this will trigger content processing for all applicable apps installed.
        """,
        version: BuildInfo.versionLine,
        subcommands: [Deploy.self, Download.self]
    )
}
