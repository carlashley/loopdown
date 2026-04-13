//// AppContentPolicy.swift
// loopdown
//
// Created on 28/3/2026
//

import Foundation


// MARK: - AppContentPolicy

/// Per-app content selection policy used under `--managed`.
///
/// When present in `ManagedPreferences.appPolicies`, the flags on this value
/// override the top-level essential/core/optional flags for the named app.
/// Apps not listed in `appPolicies` fall back to the top-level flags.
public struct AppContentPolicy: Equatable {

    /// The app this policy applies to.
    public let app: ConcreteApp

    /// Include essential content packages for this app (Logic Pro 12+ / MainStage 4+ only).
    public let essential: Bool

    /// Include core content packages for this app.
    public let core: Bool

    /// Include optional content packages for this app.
    public let optional: Bool

    public init(app: ConcreteApp, essential: Bool, core: Bool, optional: Bool) {
        self.app       = app
        self.essential = essential
        self.core      = core
        self.optional  = optional
    }
}
