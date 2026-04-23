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
        static let packageDefinitionsDir = "Application Support/Package Definitions"
    }

    // MARK: - Extract

    /// Extract a `.aar` package into `libraryDestURL` using `/usr/bin/aa extract`.
    ///
    /// Some `.aar` archives place the receipt plist outside of
    /// `Application Support/Package Definitions/`. After extraction, if the receipt plist
    /// was extracted to any location other than the expected directory, it is moved into
    /// the correct location so that subsequent receipt lookups succeed.
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

        // The receipt plist is named after the .aar filename stem and must end up in
        // Application Support/Package Definitions/. Scan the archive listing to find
        // where it actually lives so we can move it after extraction if needed.
        let stem = packageURL.deletingPathExtension().lastPathComponent
        let receiptRelativePath = findReceiptPath(in: packageURL, stem: stem, debugLog: debugLog)

        // MARK: Extract

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

        // MARK: Fixup misplaced receipt plist

        let expectedPath = "\(Consts.packageDefinitionsDir)/\(stem).plist"
        if let actualPath = receiptRelativePath, actualPath != expectedPath {
            fixupReceiptPlist(
                stem: stem,
                extractedRelativePath: actualPath,
                libraryDestURL: libraryDestURL,
                debugLog: debugLog,
                errorLog: errorLog
            )
        }
    }

    // MARK: - Receipt location scan

    /// Scan `aa list` output for the receipt plist matching `stem` and return its
    /// relative path within the archive, or `nil` if not found.
    private static func findReceiptPath(
        in packageURL: URL,
        stem: String,
        debugLog: ((String) -> Void)?
    ) -> String? {
        let listCmd = [Consts.aaPath, "list", "-i", packageURL.path]

        guard let result = try? ProcessRunner.run(
            listCmd,
            captureOutput: true,
            check: true,
            debugLog: debugLog
        ) else {
            debugLog?("AARExtractor: could not list '\(packageURL.lastPathComponent)'; skipping receipt fixup check")
            return nil
        }

        let target = "\(stem).plist"

        for line in result.stdoutString.components(separatedBy: "\n") {
            let entry = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Match any path whose last component is exactly "<stem>.plist"
            guard (entry as NSString).lastPathComponent == target else { continue }
            debugLog?("AARExtractor: found receipt plist at '\(entry)' in '\(packageURL.lastPathComponent)'")
            return entry
        }

        debugLog?("AARExtractor: no receipt plist found for '\(stem)' in '\(packageURL.lastPathComponent)'")
        return nil
    }

    // MARK: - Receipt plist fixup

    /// Move an extracted receipt plist into `Application Support/Package Definitions/`.
    private static func fixupReceiptPlist(
        stem: String,
        extractedRelativePath: String,
        libraryDestURL: URL,
        debugLog: ((String) -> Void)?,
        errorLog: ((String) -> Void)?
    ) {
        let fm = FileManager.default
        let src = libraryDestURL.appendingPathComponent(extractedRelativePath)
        let destDir = libraryDestURL.appendingPathComponent(Consts.packageDefinitionsDir, isDirectory: true)
        let dst = destDir.appendingPathComponent("\(stem).plist")

        guard fm.fileExists(atPath: src.path) else {
            debugLog?("AARExtractor: expected receipt at '\(src.path)' but not found; skipping fixup")
            return
        }

        debugLog?("AARExtractor: moving receipt '\(stem).plist' to Package Definitions")

        do {
            if !fm.fileExists(atPath: destDir.path) {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            }
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.moveItem(at: src, to: dst)
            debugLog?("AARExtractor: receipt moved to '\(dst.path)'")
        } catch {
            errorLog?("AARExtractor: failed to move receipt '\(stem).plist': \(error)")
        }
    }
}
