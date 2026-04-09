//// PackageInstaller.swift
// loopdown
//
// Created on 14/3/2026
//

import Foundation


// MARK: - Package Installer
/// Installs a `.pkg` file using `/usr/sbin/installer`.
///
/// Success or failure is determined entirely by the exit code of `installer`.
/// stdout/stderr output is forwarded to the provided debug/error log closures.
public enum PackageInstaller {

    // MARK: Errors

    public enum InstallError: Error, CustomStringConvertible {
        case installerNotFound
        case installFailed(packageName: String, returnCode: Int32, output: String)

        public var description: String {
            switch self {
            case .installerNotFound:
                return "'/usr/sbin/installer' not found or not executable."
            case .installFailed(let name, let code, let output):
                return "Failed to install '\(name)' (exit \(code)): \(output)"
            }
        }
    }

    // MARK: Constants

    private enum Consts {
        static let installerPath = "/usr/sbin/installer"
        static let target = "/"
    }

    // MARK: - Install

    /// Install a package file using `/usr/sbin/installer -pkg <pkg> -target /`.
    ///
    /// - Parameters:
    ///   - pkgURL: File URL of the `.pkg` to install.
    ///   - packageName: Human-readable package name, used only in log and error messages.
    ///   - debugLog: Optional closure receiving debug-level messages.
    ///   - errorLog: Optional closure receiving error-level messages.
    ///
    /// - Throws: `InstallError.installerNotFound` if `/usr/sbin/installer` is missing,
    ///           `InstallError.installFailed` if `installer` exits non-zero.
    public static func install(
        pkgURL: URL,
        packageName: String,
        verbose: Bool = false,
        debugLog: ((String) -> Void)? = nil,
        errorLog: ((String) -> Void)? = nil
    ) throws {
        guard FileManager.default.isExecutableFile(atPath: Consts.installerPath) else {
            throw InstallError.installerNotFound
        }

        var cmd = [Consts.installerPath]
        if verbose { cmd.append("-verbose") }
        cmd += ["-pkg", pkgURL.path, "-target", Consts.target]

        let result = try ProcessRunner.run(
            cmd,
            captureOutput: true,
            check: false,           // check manually so we can surface installer's own output
            debugLog: debugLog
        )

        // Combine stdout and stderr into a single trimmed string for log/error messages.
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
            throw InstallError.installFailed(
                packageName: packageName,
                returnCode: result.returnCode,
                output: combinedOutput
            )
        }
    }
}
