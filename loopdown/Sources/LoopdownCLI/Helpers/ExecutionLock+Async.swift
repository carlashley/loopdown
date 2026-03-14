//// ExecutionLock+Async.swift
// loopdown
//
// Created on 5/2/2026
//

import Foundation
import ArgumentParser
import LoopdownInfrastructure

extension ExecutionLock {
    /// Async-native wrapper so `AsyncParsableCommand` can still use the lock.
    ///
    /// Acquires the `flock`-based execution lock on a detached background thread
    /// so the Swift concurrency thread pool is not blocked while the async body runs.
    /// The body executes on the cooperative thread pool; the background thread simply
    /// waits for a continuation to signal completion before releasing the lock and exiting.
    static func withLockAsync(_ body: @escaping () async throws -> Void) async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Acquire the lock and run the body on a detached thread so we never
                // block a cooperative-pool thread with the flock call or the inner wait.
                Thread.detachNewThread {
                    do {
                        try ExecutionLock.withLock {
                            // Bridge into async: schedule body on the cooperative pool and
                            // block this background thread until it finishes.
                            // Use a DispatchSemaphore + ResultBox to ferry the outcome back
                            // without mutating a captured var from concurrent contexts.
                            let innerSem = DispatchSemaphore(value: 0)
                            let resultBox = ResultBox<Void>()

                            Task {
                                do {
                                    try await body()
                                    resultBox.store(.success(()))
                                } catch {
                                    resultBox.store(.failure(error))
                                }
                                innerSem.signal()
                            }

                            innerSem.wait()

                            try resultBox.take().get()
                        }
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch let e as ExecutionLock.LockError {
            throw ValidationError(e.description)
        }
    }
}


// MARK: - ResultBox
/// A thread-safe single-use box for passing a Result between a Task and a waiting thread.
private final class ResultBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?

    func store(_ result: Result<T, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func take() -> Result<T, Error> {
        lock.lock()
        defer { lock.unlock() }
        // Unwrap is safe: take() is only called after innerSem.wait() has returned,
        // which guarantees store() has already been called.
        return result!
    }
}
