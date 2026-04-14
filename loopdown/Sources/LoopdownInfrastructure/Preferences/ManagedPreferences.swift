//// ManagedPreferences.swift
// loopdown
//
// Created on 27/3/2026
//

import Foundation
import LoopdownCore


// MARK: - ManagedPreferences

/// Typed representation of the `BuildInfo.identifier` managed preferences domain.
///
/// All keys are optional in the preferences domain. Missing keys are filled with
/// documented sane defaults so that `loopdown deploy --managed` provides useful
/// behaviour out of the box with minimal MDM configuration.
///
/// ## MDM payload
/// Payload type:       `com.apple.managed.preferences`
/// Preference domain:  `BuildInfo.identifier`
///
/// ## Key reference
///
/// ```yaml
/// apps:
///   type: [String]
///   default: []        # empty = all installed apps
///   values: garageband, logicpro, mainstage
///
/// essential:
///   type: Bool
///   default: true      # inferred true when essential, core, and optional are all absent
///   # Selects essential content packages (ecp* — Logic Pro 12+ / MainStage 4+ only).
///
/// core:
///   type: Bool
///   default: true      # inferred true when essential, core, and optional are all absent
///   # Selects core content packages (ccp*; equivalent to required for legacy apps).
///
/// optional:
///   type: Bool
///   default: false
///
/// appPolicies:
///   type: [{app: String, essential: Bool, core: Bool, optional: Bool}]
///   default: []        # empty = use top-level flags for all apps
///   # Per-app overrides. Apps not listed fall back to the top-level flags.
///   # Example:
///   #   - app: logicpro
///   #     essential: true
///   #     core: true
///   #     optional: false
///   #   - app: garageband
///   #     essential: false
///   #     core: true
///   #     optional: true
///
/// forceDeploy:
///   type: Bool
///   default: false
///
/// skipSignatureCheck:
///   type: Bool
///   default: false
///
/// logLevel:
///   type: String
///   default: info
///   values: debug, info, notice, warning, error, critical
///
/// cacheServer:
///   type: String
///   default: auto      # inferred when both cacheServer and mirrorServer are absent
///   values: auto, http://host:port
///
/// mirrorServer:
///   type: String
///   default: ~         # absent; overrides cacheServer when present
///   values: https://host
///
/// dryRun:
///   type: Bool
///   default: false     # also overridable by --dry-run CLI flag
///
/// quietRun:
///   type: Bool
///   default: false
///
/// libraryDest:
///   type: String
///   default: /Users/Shared
///   # Parent directory under which Logic Pro Library.bundle is created.
/// ```
public struct ManagedPreferences: Equatable {

    // MARK: Properties

    /// Short app names to target. Empty means all installed apps.
    public let apps: [ConcreteApp]

    /// Include essential content packages (ecp* — Logic Pro 12+ / MainStage 4+ only).
    public let essential: Bool

    /// Include core content packages (ccp* — equivalent to required for legacy apps).
    public let core: Bool

    /// Include optional content packages.
    public let optional: Bool

    /// Per-app overrides for essential/core/optional. Empty means use global defaults for all apps.
    public let appPolicies: [AppContentPolicy]

    /// Force deploy regardless of existing install state.
    public let forceDeploy: Bool

    /// Skip pkgutil signature check on downloaded packages.
    public let skipSignatureCheck: Bool

    /// Minimum log level.
    public let logLevel: AppLogLevel

    /// Cache server to use. `.auto` means attempt discovery.
    public let cacheServer: CacheServer?

    /// Mirror server base URL. When non-nil, takes precedence over `cacheServer`.
    public let mirrorServer: MirrorServer?

    /// Dry run flag. May be overridden to `true` by the `--dry-run` CLI flag.
    public let dryRun: Bool

    /// Suppress all console output.
    public let quietRun: Bool

    /// Parent directory under which the library bundle is created.
    public let libraryDest: String
}
