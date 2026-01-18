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

/*
 Usage:
 let logger = Log.category("Receipts")
 let receipt = try PackageReceipt.loadIfInstalled(
     "com.apple.pkg.GarageBand10Content",
     debugLog: { logger.debug($0) }
 )
 */
