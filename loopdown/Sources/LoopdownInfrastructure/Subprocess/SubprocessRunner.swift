//// SubprocessRunner.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation


// MARK: - Output truncate helper
func truncateOutput(_ s: String, limit: Int = 4096) -> String {
    s.count > limit ? String(s.prefix(limit)) + "...<truncated>" : s
}


// MARK: - Types

/// Similar to Python's CompletedProcess.
struct CompletedProcess: Sendable {
    let args: [String]
    let returnCode: Int32
    let stdout: Data
    let stderr: Data

    var stdoutString: String { String(data: stdout, encoding: .utf8) ?? "" }
    var stderrString: String { String(data: stderr, encoding: .utf8) ?? "" }

    var succeeded: Bool { returnCode == 0 }
}

/// Errors thrown by ProcessRunner.
enum ProcessRunnerError: Error, CustomStringConvertible {
    case invalidArguments
    case launchFailed(String)
    case timedOut(seconds: TimeInterval, args: [String])
    case nonZeroExit(returnCode: Int32, args: [String], stdout: Data, stderr: Data)

    var description: String {
        switch self {
        case .invalidArguments:
            return "Invalid arguments: expected at least an executable path."
        case .launchFailed(let msg):
            return "Failed to launch process: \(msg)"
        case .timedOut(let seconds, let args):
            return "Process timed out after \(seconds)s: \(args.joined(separator: " "))"
        case .nonZeroExit(let returnCode, let args, _, _):
            return "Process exited with code \(returnCode): \(args.joined(separator: " "))"
        }
    }
}

// MARK: - Runner

// debugLog usage in other files:
// let logger = Log.category("Subprocess")
// let result = try ProcessRunner.run(cmd, check: true, debugLog: { logger.debug($0) })
enum ProcessRunner {
    /// Rough analogue to Python's subprocess.run().
    ///
    /// - Parameters:
    ///   - args: Full argv; args[0] is the executable path.
    ///   - cwd: Working directory.
    ///   - env: Environment variables (merged over current environment).
    ///   - stdin: Optional stdin payload.
    ///   - captureOutput: If false, stdout/stderr inherit the parent process streams.
    ///   - check: If true, throw if return code != 0.
    ///   - timeout: Kill process if it runs longer than this many seconds.
    ///   - debugLog: Optional logger for debug messages.
    ///
    /// - Returns: CompletedProcess with captured stdout/stderr (empty Data if not captured).
    @discardableResult
    static func run(
        _ args: [String],
        cwd: URL? = nil,
        env: [String: String]? = nil,
        stdin: Data? = nil,
        captureOutput: Bool = true,
        check: Bool = false,
        timeout: TimeInterval? = nil,
        debugLog: ((String) -> Void)? = nil
    ) throws -> CompletedProcess {
        guard let exe = args.first, !exe.isEmpty else {
            throw ProcessRunnerError.invalidArguments
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = Array(args.dropFirst())
        if let cwd { proc.currentDirectoryURL = cwd }

        // Merge environment over current environment (Python-like)
        if let env {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in env { merged[k] = v }
            proc.environment = merged
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        
        // Buffers to be filled incrementally while the process runs.
        let stdoutBuffer = LockedData()
        let stderrBuffer = LockedData()
        
        // An exit semaphore to signal exit.
        let exitSem = DispatchSemaphore(value: 0)
        
        // Termination handler fires on a background queue.
        proc.terminationHandler = { _ in exitSem.signal() }

        if captureOutput {
            proc.standardOutput = stdoutPipe
            proc.standardError = stderrPipe
            
            // Drain stdout/stderr as data becomes available to avoid pipe deadlock
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { stdoutBuffer.append(chunk) }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { stderrBuffer.append(chunk) }
            }
        } else {
            proc.standardOutput = FileHandle.standardOutput
            proc.standardError = FileHandle.standardError
        }

        let stdinData = stdin
        if stdinData != nil {
            proc.standardInput = stdinPipe
        } else {
            // Inherit stdin by default
            proc.standardInput = FileHandle.standardInput
        }

        debugLog?("Running: \(args.joined(separator: " "))")

        do {
            try proc.run()
        } catch {
            throw ProcessRunnerError.launchFailed(String(describing: error))
        }

        // Write stdin (if provided)
        if let data = stdinData {
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: data)
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                // If stdin write fails, terminate process (best effort)
                proc.terminate()
                throw ProcessRunnerError.launchFailed("Unable to write stdin: \(error)")
            }
        }
        // Alwas close the write end so the child sees EOF
        try? stdinPipe.fileHandleForWriting.close()

        
        // Wait for exit with timeout support
        if let timeout {
            let deadline = DispatchTime.now() + timeout
            if exitSem.wait(timeout: deadline) == .timedOut {
                // Stop readability handlers first (avoid callbacks after kill)
                if captureOutput {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                }

                proc.terminate()
                // Give it a moment then SIGKILL if still running
                Thread.sleep(forTimeInterval: 0.25)
                if proc.isRunning {
                    proc.kill()
                }

                // Ensure it actually exits
                _ = exitSem.wait(timeout: .now() + 1.0)

                throw ProcessRunnerError.timedOut(seconds: timeout, args: args)
            }
        } else {
            _ = exitSem.wait(timeout: .distantFuture)
        }

        // Process exited. Stop handlers and read any final buffered data.
        if captureOutput {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            // One last drain: after termination there may still be data queued.
            let finalOut = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
            let finalErr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            if !finalOut.isEmpty { stdoutBuffer.append(finalOut) }
            if !finalErr.isEmpty { stderrBuffer.append(finalErr) }
        }
        
        // Collect termination status code
        let code = proc.terminationStatus

        // Collect output (empty if not captured)
        let outData = captureOutput ? stdoutBuffer.data : Data()
        let errData = captureOutput ? stderrBuffer.data : Data()

        // Result
        let result = CompletedProcess(args: args, returnCode: code, stdout: outData, stderr: errData)

        if check, code != 0 {
            throw ProcessRunnerError.nonZeroExit(
                returnCode: code,
                args: args,
                stdout: outData,
                stderr: errData
            )
        }

        return result
    }
    
    // MARK: = Helpers
    
    /// Thread safe Data accumulator for readabilityHandler callbacks.
    private final class LockedData {
        private let lock = NSLock()
        private var storage = Data()
        
        func append(_ data: Data) {
            lock.lock()
            storage.append(data)
            lock.unlock()
        }
        
        var data: Data {
            lock.lock()
            let copy = storage
            lock.unlock()
            return copy
        }
    }

    /// Convenience for text stdin.
    @discardableResult
    static func runText(
        _ args: [String],
        cwd: URL? = nil,
        env: [String: String]? = nil,
        stdin: String,
        captureOutput: Bool = true,
        check: Bool = false,
        timeout: TimeInterval? = nil,
        debugLog: ((String) -> Void)? = nil
    ) throws -> CompletedProcess {
        try run(
            args,
            cwd: cwd,
            env: env,
            stdin: stdin.data(using: .utf8),
            captureOutput: captureOutput,
            check: check,
            timeout: timeout,
            debugLog: debugLog
        )
    }

}

private extension Process {
    func kill() {
        #if canImport(Darwin)
        if self.isRunning, self.processIdentifier > 0 {
            _ = Darwin.kill(self.processIdentifier, SIGKILL)
        }
        #else
        // On non-Darwin platforms, terminate is the best we can do without extra work.
        self.terminate()
        #endif
    }
}


/*
 usage:
 let logger = Log.category("Subprocess")
 let result = try ProcessRunner.runText(
     cmd,
     stdin: "hello",
     check: true,
     debugLog: { logger.debug($0) }
 )

 */
