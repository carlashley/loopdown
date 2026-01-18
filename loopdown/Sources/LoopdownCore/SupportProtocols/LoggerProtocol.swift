//// CoreLogger.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation


// MARK: - Protocol for logging to avoid importing LoopdownInfrastructure
/// Minimal logging interface for Core models.
///
/// LoopdownCore must not depend on LoopdownInfrastructure.
/// Infrastructure or CLI can adapt their logger to this protocol.
public protocol CoreLogger: Sendable {
    func debug(_ message: String)
    func info(_ message: String)
    func notice(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
}

/// Default no-op logger.
public struct NullLogger: CoreLogger {
    public init() {}
    public func debug(_ message: String) {}
    public func info(_ message: String) {}
    public func notice(_ message: String) {}
    public func warning(_ message: String) {}
    public func error(_ message: String) {}
}
