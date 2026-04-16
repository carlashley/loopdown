//// DownloadClient.swift
// loopdown
//
// Created on 5/2/2026
//

import Foundation

// MARK: - Progress

public struct DownloadProgress: Sendable {
    public let bytesWritten: Int64
    public let totalBytesExpected: Int64

    public var fractionCompleted: Double {
        guard totalBytesExpected > 0 else { return 0 }
        return Double(bytesWritten) / Double(totalBytesExpected)
    }
}

public enum DownloadClientError: Error, CustomStringConvertible {
    case tooManyRedirects(max: Int)
    case invalidHTTPStatus(code: Int)
    case failedToPreserveTempFile(Error)
    case cancelled

    public var description: String {
        switch self {
        case .tooManyRedirects(let max):
            return "Too many redirects (max \(max))."
        case .invalidHTTPStatus(let code):
            return "Unexpected HTTP status code: \(code)."
        case .failedToPreserveTempFile(let error):
            return "Failed to preserve downloaded temp file: \(error)"
        case .cancelled:
            return "Download cancelled."
        }
    }
}

// MARK: - DownloadClient

public final class DownloadClient: NSObject, @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (DownloadProgress) -> Void

    private let maxRedirects: Int
    private let configuration: URLSessionConfiguration

    // Optional rather than lazy: accessing a lazy stored property in deinit is
    // unsafe in Swift — if never initialised the lazy closure fires against a
    // partially-deallocated self. Using Optional lets deinit guard safely.
    private var session: URLSession?

    private struct TaskState {
        var redirects: Int
        var progress: ProgressHandler?
        var continuation: CheckedContinuation<URL, Error>?
    }

    private let lock = NSLock()
    private var states: [Int: TaskState] = [:]  // taskIdentifier -> state

    public init(
        configuration: URLSessionConfiguration = .default,
        maxRedirects: Int = 5
    ) {
        self.maxRedirects = maxRedirects

        // Copy & configure for a CLI tool.
        let cfg = configuration.copy() as! URLSessionConfiguration
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 60 * 60
        self.configuration = cfg

        super.init()
    }

    deinit {
        // Only invalidate if the session was ever created.
        // Accessing a never-initialised lazy property in deinit would trigger
        // its initialiser against a partially-deallocated self, causing a crash.
        session?.invalidateAndCancel()
    }

    /// Returns the shared URLSession, creating it on first use.
    private func makeSessionIfNeeded() -> URLSession {
        if let existing = session { return existing }
        let s = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session = s
        return s
    }

    /// NSURLError codes that indicate a transient network condition worth retrying.
    private static let retryableURLErrorCodes: Set<Int> = [
        // Connection state
        NSURLErrorNetworkConnectionLost,
        NSURLErrorNotConnectedToInternet,
        NSURLErrorBackgroundSessionWasDisconnected,
        // Host/DNS resolution
        NSURLErrorCannotConnectToHost,
        NSURLErrorCannotFindHost,
        NSURLErrorDNSLookupFailed,
        // Timeouts
        NSURLErrorTimedOut,
        // TLS — can be transient under load or during cert rotation
        NSURLErrorSecureConnectionFailed,
    ]

    /// Downloads a file and returns a stable URL the caller owns.
    ///
    /// Retries on transient network errors up to `maxRetries` times, with an
    /// exponential backoff starting at `retryDelay` seconds.
    ///
    /// URLSession's `didFinishDownloadingTo` location is temporary and is deleted
    /// as soon as that delegate method returns. To hand back a durable URL, the
    /// file is moved to a new temp path *inside* the delegate callback before the
    /// continuation is resumed. The caller is responsible for deleting the file
    /// when done.
    public func downloadTempFile(
        from url: URL,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 2,
        onRetry: (@Sendable (Int, Int, Error) -> Void)? = nil,
        progress: ProgressHandler? = nil
    ) async throws -> URL {

        var attempt = 0
        var delay   = retryDelay

        while true {
            do {
                return try await attemptDownload(from: url, progress: progress)
            } catch {
                let code = (error as NSError).code
                guard attempt < maxRetries,
                      Self.retryableURLErrorCodes.contains(code)
                else { throw error }

                attempt += 1
                onRetry?(attempt, maxRetries, error)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay *= 2
            }
        }
    }

    /// Single download attempt — no retry logic.
    private func attemptDownload(
        from url: URL,
        progress: ProgressHandler? = nil
    ) async throws -> URL {

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let task = makeSessionIfNeeded().downloadTask(with: request)

        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            states[task.taskIdentifier] = TaskState(
                redirects: 0,
                progress: progress,
                continuation: cont
            )
            lock.unlock()

            task.resume()
        }
    }

    // MARK: - State helpers

    private func withState<T>(_ taskID: Int, _ body: (inout TaskState) -> T) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard var s = states[taskID] else { return nil }
        let out = body(&s)
        states[taskID] = s
        return out
    }

    private func popState(_ taskID: Int) -> TaskState? {
        lock.lock()
        defer { lock.unlock() }
        return states.removeValue(forKey: taskID)
    }
}

// MARK: - URLSession delegates

extension DownloadClient: URLSessionTaskDelegate, URLSessionDownloadDelegate {

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let shouldCancel: Bool = withState(task.taskIdentifier) { state in
            state.redirects += 1
            return state.redirects > maxRedirects
        } ?? false

        if shouldCancel {
            if let state = popState(task.taskIdentifier) {
                state.continuation?.resume(throwing: DownloadClientError.tooManyRedirects(max: maxRedirects))
            }
            completionHandler(nil)
            task.cancel()
            return
        }

        completionHandler(request)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return } // success handled in didFinishDownloadingTo

        guard let state = popState(task.taskIdentifier) else { return }

        if (error as NSError).code == NSURLErrorCancelled {
            state.continuation?.resume(throwing: DownloadClientError.cancelled)
        } else {
            state.continuation?.resume(throwing: error)
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        _ = withState(downloadTask.taskIdentifier) { state in
            state.progress?(
                DownloadProgress(
                    bytesWritten: totalBytesWritten,
                    totalBytesExpected: totalBytesExpectedToWrite
                )
            )
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse {
            if !(200...299).contains(http.statusCode) {
                if let state = popState(downloadTask.taskIdentifier) {
                    state.continuation?.resume(throwing: DownloadClientError.invalidHTTPStatus(code: http.statusCode))
                }
                return
            }
        }

        guard let state = popState(downloadTask.taskIdentifier) else { return }

        // The file at `location` is owned by URLSession and will be deleted the
        // moment this delegate method returns. Move it to a stable temp path now,
        // before resuming the continuation, so the caller receives a durable URL.
        let stableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)

        do {
            try FileManager.default.moveItem(at: location, to: stableURL)
            state.continuation?.resume(returning: stableURL)
        } catch {
            state.continuation?.resume(throwing: DownloadClientError.failedToPreserveTempFile(error))
        }
    }
}
