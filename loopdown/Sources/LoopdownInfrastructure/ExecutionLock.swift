//// ExecutionLock.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation
#if canImport(Darwin)
import Darwin
#endif


// MARK: - Execution locking
/// Prevent multiple instances of loopdown from running concurrently.
public enum ExecutionLock {

    public enum LockError: Error, CustomStringConvertible {
        case alreadyRunning
        case openFailed(String)

        public var description: String {
            switch self {
            case .alreadyRunning:
                return "Another instance of loopdown is already running."
            case .openFailed(let msg):
                return msg
            }
        }
    }

    /// Default lock file path.
    private static let lockPath = "/tmp/loopdown.lock"

    /// Acquire the execution lock and run `body`.
    ///
    /// The lock is held for the lifetime of `body`.
    /// It is automatically released if the process exits or crashes.
    public static func withLock<T>(
        _ body: () throws -> T
    ) throws -> T {

        let fd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH)
        guard fd >= 0 else {
            throw LockError.openFailed("Unable to open lock file at \(lockPath)")
        }

        // Ensure world-writable so sudo/non-sudo runs don't fight permissions
        _ = chmod(lockPath, 0o666)

        // Try to acquire exclusive, non-blocking lock
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            throw LockError.alreadyRunning
        }

        // Hold fd open for the lifetime of body
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }

        return try body()
    }
}
