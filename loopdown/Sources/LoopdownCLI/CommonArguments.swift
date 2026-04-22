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

    /// True when the log level is debug or below; passed to ContentCoordinator as verboseInstall
    var isVerbose: Bool { logLevel <= .debug }
}

struct EssentialContentOption: ParsableArguments {
    @Flag(
        name: [.customShort("e"), .customLong("essential")],
        help: "Include essential audio packages (Logic Pro 12+ and MainStage 4+ only)."
    )
    var essential: Bool = false
}

struct CoreContentOption: ParsableArguments {
    @Flag(
        name: [.customShort("r"), .customLong("core")],
        help: "Include core audio packages (equivalent to -r, --req for legacy applications)."
    )
    var core: Bool = false
}

struct OptionalContentOption: ParsableArguments {
    @Flag(name: [.customShort("o"), .customLong("optional")], help: "Include optional content.")
    var optional: Bool = false
}

struct SkipSignatureCheckOption: ParsableArguments {
    @Flag(name: .long, help: "Skip the pkgutil signature check on downloaded packages (legacy content only).")
    var skipSignatureCheck: Bool = false
}

struct DownloadRetryOptions: ParsableArguments {
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Maximum number of download retry attempts on transient network errors (1-10, default: 3).",
            valueName: "n"
        )
    )
    var maxRetries: Int? = nil

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Initial backoff delay in seconds between download retry attempts (1-5, default: 2).",
            valueName: "seconds"
        )
    )
    var backoffSleep: Int? = nil

    var effectiveMaxRetries:  Int { maxRetries   ?? 3 }
    var effectiveBackoffSleep: Int { backoffSleep ?? 2 }

    mutating func validate() throws {
        if let v = maxRetries, !(1...10).contains(v) {
            throw ValidationError("'--max-retries' must be between 1 and 10.")
        }
        if let v = backoffSleep, !(1...5).contains(v) {
            throw ValidationError("'--backoff-sleep' must be between 1 and 5.")
        }
    }
}

struct DownloadBandwidthOptions: ParsableArguments {
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Abort download if rolling average speed stays below this threshold (e.g. 300KB or 2MB).",
            valueName: "speed"
        )
    )
    var minimumBandwidth: String? = nil

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Rolling average window in seconds for bandwidth measurement (30-120, default: 60).",
            valueName: "seconds"
        )
    )
    var bandwidthTimeout: Int? = nil

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Abort the run after this many consecutive bandwidth-threshold failures (2-5, default: 3). Requires --minimum-bandwidth.",
            valueName: "n"
        )
    )
    var abortAfter: Int? = nil

    /// Parsed minimum bandwidth in bytes/sec, or nil if not specified.
    var minimumBandwidthBytesPerSec: Int? {
        guard let raw = minimumBandwidth else { return nil }
        return DownloadBandwidthOptions.parseBytesPerSec(raw)
    }

    var effectiveBandwidthTimeout: Int { bandwidthTimeout ?? 60 }
    var effectiveAbortAfter: Int       { abortAfter       ?? 3  }

    /// Effective abort-after value; nil when no minimum bandwidth threshold is set.
    var effectiveBandwidthAbortAfter: Int? {
        minimumBandwidth != nil ? effectiveAbortAfter : nil
    }

    mutating func validate() throws {
        if let raw = minimumBandwidth {
            guard let bps = DownloadBandwidthOptions.parseBytesPerSec(raw) else {
                throw ValidationError("'--minimum-bandwidth' must be in the form <N>KB or <N>MB (e.g. 300KB or 2MB).")
            }
            let min = 300 * 1024           // 300 KB/s
            let max = 5 * 1024 * 1024      // 5 MB/s
            guard (min...max).contains(bps) else {
                throw ValidationError("'--minimum-bandwidth' must be between 300KB/s and 5MB/s.")
            }
        }
        if let v = bandwidthTimeout, !(30...120).contains(v) {
            throw ValidationError("'--bandwidth-timeout' must be between 30 and 120 seconds.")
        }
        if let v = abortAfter {
            if minimumBandwidth == nil {
                throw ValidationError("'--abort-after' requires '--minimum-bandwidth'.")
            }
            if !(2...5).contains(v) {
                throw ValidationError("'--abort-after' must be between 2 and 5.")
            }
        }
    }

    /// Parse a string like "300KB" or "2MB" into bytes/sec.
    static func parseBytesPerSec(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasSuffix("MB"), let n = Int(s.dropLast(2).trimmingCharacters(in: .whitespaces)) {
            return n * 1024 * 1024
        }
        if s.hasSuffix("KB"), let n = Int(s.dropLast(2).trimmingCharacters(in: .whitespaces)) {
            return n * 1024
        }
        return nil
    }
}
