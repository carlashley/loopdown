//// Logging.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation

#if canImport(os)
import os
#endif


// MARK: - Log Level
/// Log level threshold. Messages below the configured level are ignored.
public enum AppLogLevel: String, CaseIterable, Comparable {
    case trace
    case debug
    case info
    case notice
    case warning
    case error
    case critical

    private static let rank: [AppLogLevel: Int] = [
        .trace: 0,
        .debug: 1,
        .info: 2,
        .notice: 3,
        .warning: 4,
        .error: 5,
        .critical: 6
    ]

    public static func < (lhs: AppLogLevel, rhs: AppLogLevel) -> Bool {
        (rank[lhs] ?? 0) < (rank[rhs] ?? 0)
    }

    public init?(parsing argument: String) {
        let s = argument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch s {
        case "t", "trace": self = .trace
        case "d", "dbg", "debug": self = .debug
        case "i", "info": self = .info
        case "n", "notice": self = .notice
        case "w", "warn", "warning": self = .warning
        case "e", "err", "error": self = .error
        case "c", "crit", "critical": self = .critical
        default: return nil
        }
    }
}


// MARK: - Console Sink
/// Write log lines to stdout/stderr (stderr for warning+ by default).
/// When `isEnabled` is false, console output is suppressed.
public struct ConsoleLogSink {
    public var isEnabled: Bool = false

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    public func writeLine(_ line: String, level: AppLogLevel) {
        guard isEnabled else { return }

        let handle: FileHandle?
        switch level {
        case .info, .notice:
            handle = .standardOutput
        case .warning, .error, .critical:
            handle = .standardError
        case .trace, .debug:
            handle = nil
        }

        guard let handle,
              let data = (line + "\n").data(using: .utf8)
        else { return }

        handle.write(data)
    }

    public func enabled() -> ConsoleLogSink {
        var copy = self
        copy.isEnabled = true
        return copy
    }

    public func disabled() -> ConsoleLogSink {
        var copy = self
        copy.isEnabled = false
        return copy
    }
}


// MARK: - File Sink
/// Append log lines to file. Safe to call from multiple threads.
public final class FileLogSink {
    private let fileHandle: FileHandle
    private let queue = DispatchQueue(label: "FileLogSink.queue")

    public init(fileURL: URL) throws {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()

        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }

        self.fileHandle = try FileHandle(forWritingTo: fileURL)
        try self.fileHandle.seekToEnd()
    }

    deinit {
        try? fileHandle.close()
    }

    public func writeLine(_ line: String) {
        queue.async {
            guard let data = (line + "\n").data(using: .utf8) else { return }
            do {
                try self.fileHandle.write(contentsOf: data)
            } catch {
                // Intentionally swallow to avoid recursion.
            }
        }
    }
}


//  MARK: - AppLogger
/// A logger that emits to:
///  - Unified logging (os.Logger)
///  - Zero or more file sinks (tee)
///  - Optional console sink (message-only)
public final class AppLogger: @unchecked Sendable {
    private let osLogger: os.Logger

    public let minLevel: AppLogLevel
    public let fileSinks: [FileLogSink]
    public let consoleSink: ConsoleLogSink?

    private let subsystem: String
    private let category: String

    /// Cached timestamp formatter to avoid per-log allocation.
    private static let tsFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f
    }()

    public init(
        subsystem: String,
        category: String,
        minLevel: AppLogLevel = .info,
        fileSinks: [FileLogSink] = [],
        consoleSink: ConsoleLogSink? = nil
    ) {
        self.subsystem = subsystem
        self.category = category
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
        self.minLevel = minLevel
        self.fileSinks = fileSinks
        self.consoleSink = consoleSink
    }

    public func log(
        _ level: AppLogLevel,
        _ message: String,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        guard level >= minLevel else { return }

        consoleSink?.writeLine(message, level: level)

        if !fileSinks.isEmpty {
            let ts = Self.tsFormatter.string(from: Date())
            let levelStr = level.rawValue.uppercased()
            let paddedLevel = levelStr.padding(toLength: 8, withPad: " ", startingAt: 0)
            let renderedFile = "\(ts) [\(paddedLevel)] \(message) (\(file):\(line) \(function))"
            for sink in fileSinks { sink.writeLine(renderedFile) }
        }

        switch level {
        case .trace, .debug:
            osLogger.debug("\(message, privacy: .public)")
        case .info:
            osLogger.info("\(message, privacy: .public)")
        case .notice:
            osLogger.notice("\(message, privacy: .public)")
        case .warning:
            osLogger.warning("\(message, privacy: .public)")
        case .error:
            osLogger.error("\(message, privacy: .public)")
        case .critical:
            osLogger.critical("\(message, privacy: .public)")
        }
    }

    public func trace(_ msg: String)    { log(.trace, msg) }
    public func debug(_ msg: String)    { log(.debug, msg) }
    public func info(_ msg: String)     { log(.info, msg) }
    public func notice(_ msg: String)   { log(.notice, msg) }
    public func warning(_ msg: String)  { log(.warning, msg) }
    public func error(_ msg: String)    { log(.error, msg) }
    public func critical(_ msg: String) { log(.critical, msg) }

    public func withConsole(_ sink: ConsoleLogSink?) -> AppLogger {
        AppLogger(
            subsystem: subsystem,
            category: category,
            minLevel: minLevel,
            fileSinks: fileSinks,
            consoleSink: sink
        )
    }

    public func withFileSinks(_ sinks: [FileLogSink]) -> AppLogger {
        AppLogger(
            subsystem: subsystem,
            category: category,
            minLevel: minLevel,
            fileSinks: sinks,
            consoleSink: consoleSink
        )
    }
}


// MARK: - Log helper (deferred start)
public enum Log {
    /// Shared configuration logger. Starts with NO file sinks and console disabled.
    public private(set) static var shared = AppLogger(
        subsystem: "com.github.carlashley.loopdown",
        category: "app",
        minLevel: .info,
        fileSinks: [],
        consoleSink: ConsoleLogSink(isEnabled: false)
    )

    /// Where loopdown logs live (created lazily).
    public static let logDirectoryURL = URL(fileURLWithPath: "/Users/Shared/loopdown", isDirectory: true)

    /// Run log URL (set once startRunLogging succeeds).
    public private(set) static var runLogURL: URL? = nil

    /// Configure baseline logger settings (no file creation).
    public static func configureBase(
        subsystem: String,
        minLevel: AppLogLevel = .info,
        consoleEnabled: Bool = false
    ) {
        let consoleSink = ConsoleLogSink(isEnabled: consoleEnabled)
        shared = AppLogger(
            subsystem: subsystem,
            category: "app",
            minLevel: minLevel,
            fileSinks: [],
            consoleSink: consoleSink
        )
    }

    public static func enableConsoleOutput() {
        guard let sink = shared.consoleSink else { return }
        shared = shared.withConsole(sink.enabled())
    }

    public static func disableConsoleOutput() {
        guard let sink = shared.consoleSink else { return }
        shared = shared.withConsole(sink.disabled())
    }

    @discardableResult
    public static func startRunLogging(
        keepLatestCopy: Bool = true,
        keepMostRecentRuns: Int = 5
    ) -> URL? {
        if let existing = runLogURL { return existing }

        let fm = FileManager.default

        do {
            try fm.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        pruneOldRunLogs(keepingMostRecent: keepMostRecentRuns)

        let stamp = runStamp()
        let runURL = logDirectoryURL.appendingPathComponent("loopdown-\(stamp).log", isDirectory: false)

        var sinks: [FileLogSink] = []
        if let runSink = try? FileLogSink(fileURL: runURL) { sinks.append(runSink) }

        if keepLatestCopy {
            let latestURL = logDirectoryURL.appendingPathComponent("latest.log", isDirectory: false)
            _ = try? fm.removeItem(at: latestURL)
            if let latestSink = try? FileLogSink(fileURL: latestURL) { sinks.append(latestSink) }
        }

        shared = shared.withFileSinks(sinks)
        runLogURL = runURL
        return runURL
    }

    public static func category(_ name: String) -> AppLogger {
        AppLogger(
            subsystem: "com.github.carlashley.loopdown",
            category: name,
            minLevel: shared.minLevel,
            fileSinks: shared.fileSinks,
            consoleSink: shared.consoleSink
        )
    }

    private static func runStamp() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df.string(from: Date())
    }

    private static func pruneOldRunLogs(keepingMostRecent keep: Int) {
        let fm = FileManager.default
        let dir = logDirectoryURL

        guard let items = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let runLogs = items.filter {
            $0.lastPathComponent.hasPrefix("loopdown-") && $0.pathExtension == "log"
        }

        let sorted = runLogs.sorted {
            let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d0 > d1
        }

        for url in sorted.dropFirst(keep) {
            _ = try? fm.removeItem(at: url)
        }
    }
}
