//// AppContentPolicy.swift
// loopdown
//
// Created on 28/3/2026
//
    

import Foundation


// MARK: - AppContentPolicy

/// Per-app content selection policy used under `--managed`.
///
/// When present in `ManagedPreferences.appPolicies`, the `required` and `optional`
/// flags on this value override the top-level `required`/`optional` for the named app.
/// Apps not listed in `appPolicies` fall back to the top-level flags.
public struct AppContentPolicy: Equatable {

    /// The app this policy applies to.
    public let app: ConcreteApp

    /// Include required content packages for this app.
    public let required: Bool

    /// Include optional content packages for this app.
    public let optional: Bool

    public init(app: ConcreteApp, required: Bool, optional: Bool) {
        self.app      = app
        self.required = required
        self.optional = optional
    }
}
