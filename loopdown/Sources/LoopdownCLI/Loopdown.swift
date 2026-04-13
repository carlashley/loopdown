//// Loopdown.swift
// loopdown
//
// Created on 18/1/2026
//
    

import ArgumentParser
import LoopdownCore

@main
struct Loopdown: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "loopdown",
        abstract: "Manage additional content for Apple's audio applications, GarageBand, Logic Pro, and/or MainStage.",
        discussion: """
        These arguments are supported in both 'deploy' and 'download' commands:
          -n, --dry-run     Perform a dry run.
          -a, --app <app>   Install content for an app (default: all supported apps).
          -e, --essential   Select essential content (Logic Pro 12+ and MainStage 4+ only).
          -r, --core        Select core content (equivalent to old -r, --req for Legacy apps).
          -o, --optional    Select optional content.

        COMMENTS:
          -e, --essential / -r, --core / -o, --optional one or more are required.
          -a, --app is not required; omitting this will trigger content processing for all applicable apps installed.
        """,
        version: BuildInfo.versionLine,
        subcommands: [Deploy.self, Download.self]
    )
}
