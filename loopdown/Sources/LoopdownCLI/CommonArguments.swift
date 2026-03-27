//// CommonArguments.swift
// loopdown
//
// Created on 18/1/2026
//

import ArgumentParser
import LoopdownInfrastructure
import LoopdownCore


// MARK: - Common arguments

struct AppOptions: ParsableArguments {
    @Option(
        name: [.short, .long],
        parsing: .upToNextOption,
        help: ArgumentHelp(
            "Install content for an app (default: all supported apps).\n",
            valueName: "app"
        )
    )
    var app: [ConcreteApp] = []
}

struct DryRunOption: ParsableArguments {
    @Flag(name: [.customShort("n"), .long], help: "Perform a dry run.")
    var dryRun: Bool = false
}

struct QuietRunOption: ParsableArguments {
    @Flag(name: [.short, .long], help: "Suppress all console output.")
    var quietRun: Bool = false
}

struct LoggingOptions: ParsableArguments {
    @Option(name: .long)
    var logLevel: AppLogLevel = .info
}

struct RequiredContentOption: ParsableArguments {
    @Flag(name: [.short, .long], help: "Select required content.")
    var required: Bool = false
}

struct OptionalContentOption: ParsableArguments {
    @Flag(name: [.short, .long], help: "Select optional content.")
    var optional: Bool = false
}

struct SkipSignatureCheckOption: ParsableArguments {
    @Flag(name: .long, help: "Skip the pkgutil signature check on downloaded packages.")
    var skipSignatureCheck: Bool = false
}
