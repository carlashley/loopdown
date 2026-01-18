//// SystemProfiler.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation


// MARK: - System Profiler
public enum SystemProfilerDataType: String {
    case applications = "SPApplicationsDataType"
}

public enum SystemProfilerDetailLevel: String {
    case basic, full, mini
}

public enum SystemProfiler {
    public static func run(
        _ type: SystemProfilerDataType,
        detailLevel: SystemProfilerDetailLevel = .full,
        debugLog: ((String) -> Void)? = nil
    ) -> [[String: Any]]? {
        let cmd = ["/usr/sbin/system_profiler", "-json", "-detaillevel", detailLevel.rawValue, type.rawValue]

        do {
            let result = try ProcessRunner.run(cmd, captureOutput: true, check: true, debugLog: debugLog)
            let obj = try JSONSerialization.jsonObject(with: result.stdout)

            guard let root = obj as? [String: Any] else {
                debugLog?("'system_profiler' returned non-dictionary JSON.")
                return nil
            }

            guard let data = root[type.rawValue] as? [[String: Any]] else { return nil }
            return data

        } catch let error as ProcessRunnerError {
            switch error {
            case .nonZeroExit(let returnCode, let args, let stdout, let stderr):
                debugLog?("'system_profiler' exited with code \(returnCode). cmd='\(args.joined(separator: " "))'")
                let out = String(data: stdout, encoding: .utf8) ?? "<non-utf8 stdout>"
                let err = String(data: stderr, encoding: .utf8) ?? "<non-utf8 stderr>"
                if !out.isEmpty { debugLog?("stdout: \(truncateOutput(out))") }
                if !err.isEmpty { debugLog?("stderr: \(truncateOutput(err))") }
                return nil
            default:
                debugLog?("'system_profiler' failed: \(error)")
                return nil
            }
        } catch {
            debugLog?("JSON decode error while parsing 'system_profiler' output: \(error)")
            return nil
        }
    }
}
