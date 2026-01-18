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
        abstract: "Manage additional content for Apple's audio applications",
        subcommands: [Deploy.self, Download.self]
    )

    @Flag(name: [.customShort("v"), .long])
    var version: Bool = false

    func run() throws {
        if version {
            print(BuildInfo.versionLine)
            return
        }
        print(Self.helpMessage())
    }
}
