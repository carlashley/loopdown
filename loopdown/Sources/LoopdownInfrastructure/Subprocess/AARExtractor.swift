//// AARExtractor.swift
// loopdown
//
// Created on 12/4/2026
//
    


//// AARExtractor.swift
// loopdown
//
// Created on 12/4/2026
//

import Foundation


// MARK: - AARExtractor

/// Installs a modern content package (`.aar` Apple Archive) using `/usr/bin/aa extract`.
///
/// Modern Logic Pro 12+ and MainStage 4+ content packages are `.aar` archives rather than
/// flat `.pkg` files. They are extracted directly into the Logic Pro Library bundle directory
/// instead of being installed via `/usr/sbin/installer`.
///
/// Equivalent to the Python `unpack_aar` function in `_installation_mixin.py`.
public enum AARExtractor {

    // MARK: - Errors

    public enum AARError: Error, CustomStringConvertible {
        case aaNotFound
        case extractionFailed(packageName: String, returnCode: Int32, output: String)

        public var description: String {
            switch self {
            case .aaNotFound:
                return "'/usr/bin/aa' not found or not executable."
            case .extractionFailed(let name, let code, let output):
                return "Failed to extract '\(name)' (exit \(code)): \(output)"
            }
        }
    }

    // MARK: - Constants

    private enum Consts {
        static let aaPath = "/usr/bin/aa"
    }

    // MARK: - Extract

    /// Extract a `.aar` package into `libraryDestURL` using `/usr/bin/aa extract`.
    ///
    /// Equivalent to: `aa extract -d <libraryDestURL> -i <packageURL>`
    ///
    /// - Parameters:
    ///   - packageURL: File URL of the `.aar` archive to extract.
    ///   - packageName: Human-readable name used only in log and error messages.
    ///   - libraryDestURL: Directory URL to extract content into (the Logic Pro Library bundle path).
    ///   - debugLog: Optional closure receiving debug-level messages.
    ///   - errorLog: Optional closure receiving error-level messages.
    ///
    /// - Throws: `AARError.aaNotFound` if `/usr/bin/aa` is missing,
    ///           `AARError.extractionFailed` if `aa` exits non-zero.
    public static func extract(
        packageURL: URL,
        packageName: String,
        libraryDestURL: URL,
        debugLog: ((String) -> Void)? = nil,
        errorLog: ((String) -> Void)? = nil
    ) throws {
        guard FileManager.default.isExecutableFile(atPath: Consts.aaPath) else {
            throw AARError.aaNotFound
        }

        let cmd = [
            Consts.aaPath,
            "extract",
            "-d", libraryDestURL.path,
            "-i", packageURL.path
        ]

        let result = try ProcessRunner.run(
            cmd,
            captureOutput: true,
            check: false,           // check manually so we can surface aa's own output
            debugLog: debugLog
        )

        let stdout = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
        let combinedOutput = [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if result.succeeded {
            if !combinedOutput.isEmpty {
                debugLog?(combinedOutput)
            }
        } else {
            if !combinedOutput.isEmpty {
                errorLog?(combinedOutput)
            }
            throw AARError.extractionFailed(
                packageName: packageName,
                returnCode: result.returnCode,
                output: combinedOutput
            )
        }
    }
}
