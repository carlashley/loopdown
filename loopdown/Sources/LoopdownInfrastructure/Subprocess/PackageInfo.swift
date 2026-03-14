//// PackageInfo.swift
// loopdown
//
// Created on 18/1/2026
//

import Foundation


// MARK: - Package Info
/// Receipt info for an installed package (from `/usr/sbin/pkgutil --pkg-info-plist <packageID>`).
struct PackageReceipt: Hashable {
    let packageID: String
    let version: String?

    enum ReceiptError: Error, CustomStringConvertible {
        case pkgutilNotFound
        case receiptNotFound(String)
        case invalidPlistRoot(String)
        case missingIdentifier

        var description: String {
            switch self {
            case .pkgutilNotFound:
                return "binary not found at '/usr/sbin/pkgutil'"
            case .receiptNotFound(let id):
                return "No receipt found for package id '\(id)'"
            case .invalidPlistRoot(let id):
                return "Property list root was not a dictionary for '\(id)'"
            case .missingIdentifier:
                return "Receipt property list missing 'pkgid'/'package-id'/'identifier' attribute"
            }
        }
    }

    /// Load receipt info by running `/usr/sbin/pkgutil`.
    ///
    /// - Parameters:
    ///   - packageID: The package identifier to query.
    ///   - debugLog: Optional debug logger closure.
    /// - Returns: A receipt if installed, otherwise nil.
    static func loadIfInstalled(
        _ packageID: String,
        debugLog: ((String) -> Void)? = nil
    ) throws -> PackageReceipt? {
        let pkgutil = "/usr/sbin/pkgutil"
        guard FileManager.default.isExecutableFile(atPath: pkgutil) else {
            throw ReceiptError.pkgutilNotFound
        }

        // '--pkg-info-plist' returns an XML plist on stdout
        let cmd = [pkgutil, "--pkg-info-plist", packageID]

        let result: CompletedProcess
        do {
            result = try ProcessRunner.run(
                cmd,
                captureOutput: true,
                check: true,
                debugLog: debugLog
            )
        } catch let error as ProcessRunnerError {
            // pkgutil returns exit code 1 if receipt doesn't exist; treat as "not installed"
            switch error {
            case .nonZeroExit:
                debugLog?("No receipt found for '\(packageID)'")
                return nil
            default:
                throw error
            }
        }

        let obj = try PropertyListSerialization.propertyList(
            from: result.stdout,
            options: [],
            format: nil
        )
        guard let dict = obj as? [String: Any] else {
            throw ReceiptError.invalidPlistRoot(packageID)
        }

        // pkgutil keys can vary
        let id = (dict["pkgid"] as? String)
            ?? (dict["package-id"] as? String)
            ?? (dict["identifier"] as? String)

        guard let id, !id.isEmpty else {
            throw ReceiptError.missingIdentifier
        }

        let version: String? =
            (dict["pkg-version"] as? String)
            ?? (dict["pkgversion"] as? String)

        return PackageReceipt(packageID: id, version: version)
    }
}


// MARK: - Package Signature Checker
/// Verifies a downloaded `.pkg` file is signed Apple software using
/// `/usr/sbin/pkgutil --check-signature`.
///
/// A non-zero exit code or a status line that does not contain "signed apple"
/// indicates the file is corrupt, incomplete, or not a genuine Apple package.
public enum PackageSignatureChecker {

    private static let pkgutil = "/usr/sbin/pkgutil"
    private static let statusPrefix = "Status: "

    /// Returns `true` if the package at `pkgURL` is signed Apple software.
    ///
    /// - Parameters:
    ///   - pkgURL: File URL of the `.pkg` to check.
    ///   - debugLog: Optional closure receiving debug-level messages.
    /// - Returns: `true` if signed Apple software, `false` otherwise.
    public static func isSignedAppleSoftware(
        pkgURL: URL,
        debugLog: ((String) -> Void)? = nil
    ) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: pkgutil) else {
            debugLog?("pkgutil not found at \(pkgutil); skipping signature check")
            return false
        }

        let cmd = [pkgutil, "--check-signature", pkgURL.path]

        let result: CompletedProcess
        do {
            result = try ProcessRunner.run(
                cmd,
                captureOutput: true,
                check: false,       // non-zero exit is expected for invalid/incomplete packages
                debugLog: debugLog
            )
        } catch {
            debugLog?("Error running pkgutil --check-signature for '\(pkgURL.lastPathComponent)': \(error)")
            return false
        }

        // Collect stdout lines, falling back to stderr if stdout is empty.
        let rawOutput = result.stdoutString.isEmpty ? result.stderrString : result.stdoutString
        let lines = rawOutput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Find the "Status: ..." line and check it contains "signed apple".
        let status = lines.first(where: { $0.hasPrefix(statusPrefix) })
            .map { String($0.dropFirst(statusPrefix.count)) }

        let isSigned = result.returnCode == 0
            && status != nil
            && status!.lowercased().contains("signed apple")

        debugLog?("Signature check '\(pkgURL.lastPathComponent)': status='\(status ?? "<none>")' signed=\(isSigned)")

        return isSigned
    }
}

/*
 Usage:
 let logger = Log.category("Receipts")
 let receipt = try PackageReceipt.loadIfInstalled(
     "com.apple.pkg.GarageBand10Content",
     debugLog: { logger.debug($0) }
 )

 let ok = PackageSignatureChecker.isSignedAppleSoftware(
     pkgURL: stagedURL,
     debugLog: { logger.debug($0) }
 )
 */
