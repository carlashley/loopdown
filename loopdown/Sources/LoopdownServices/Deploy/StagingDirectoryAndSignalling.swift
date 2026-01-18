//// StagingDirectoryAndSignalling.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation
#if canImport(Darwin)
import Darwin
#endif


// MARK: - Temporary directory
public final class TemporaryDirectory {
    public let url: URL
    private var shouldDelete = true

    public init(prefix: String = "loopdown-staging-", fileManager: FileManager = .default) throws {
        let base = fileManager.temporaryDirectory
        let dir = base.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        self.url = dir
    }

    func keep() { shouldDelete = false }

    public func cleanup(fileManager: FileManager = .default) {
        guard shouldDelete else { return }
        try? fileManager.removeItem(at: url)
        shouldDelete = false
    }

    deinit { cleanup() }
}


// MARK: - Signal cleanup
public final class SignalCleanup {
    private var sources: [DispatchSourceSignal] = []
    public let cleanup: () -> Void
    private var isInstalled = false

    public init(cleanup: @escaping () -> Void) {
        self.cleanup = cleanup
    }

    public func install() {
        guard !isInstalled else { return }
        isInstalled = true

        let signals: [Int32] = [SIGINT, SIGTERM, SIGHUP]

        for sig in signals {
            // Route signal delivery through DispatchSourceSignal
            signal(sig, SIG_IGN)

            let src = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            src.setEventHandler { [cleanup] in
                cleanup()
                _exit(128 + sig)
            }
            src.resume()
            sources.append(src)
        }
    }

    public func uninstall() {
        guard isInstalled else { return }
        isInstalled = false

        // Cancel sources so they stop receiving signals.
        for src in sources {
            src.cancel()
        }
        sources.removeAll()

        // Restore default handlers.
        let signals: [Int32] = [SIGINT, SIGTERM, SIGHUP]
        for sig in signals {
            signal(sig, SIG_DFL)
        }
    }

    deinit {
        uninstall()
    }
}
