//// AppGeneration.swift
// loopdown
//
// Created on 15/4/2026
//


// MARK: - AppGeneration

/// Controls which generation of installed applications are targeted during a deploy.
///
/// - `any`:        Both legacy and modern apps are targeted (default).
/// - `legacyOnly`: Only apps that use the legacy `.pkg` content delivery system are targeted.
/// - `modernOnly`: Only apps that use the modern `.aar` SQLite-based content delivery system are targeted.
@frozen public enum AppGeneration: Sendable {
    case any
    case legacyOnly
    case modernOnly
}
