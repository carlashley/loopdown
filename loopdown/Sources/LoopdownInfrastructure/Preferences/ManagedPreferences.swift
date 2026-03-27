//// ManagedPreferences.swift
// loopdown
//
// Created on 27/3/2026
//
    

import Foundation
import LoopdownCore


// MARK: - ManagedPreferences

/// Typed representation of the `com.github.carlashley.loopdown` managed preferences domain.
///
/// All keys are optional in the preferences domain. Missing keys are filled with
/// documented sane defaults so that `loopdown deploy --managed` provides useful
/// behaviour out of the box with minimal MDM configuration.
///
/// ## MDM payload
/// Payload type:       `com.apple.managed.preferences`
/// Preference domain:  `com.github.carlashley.loopdown`
///
/// ## Key reference
///
/// ```yaml
/// apps:
///   type: [String]
///   default: []        # empty = all installed apps
///   values: garageband, logicpro, mainstage
///
/// required:
///   type: Bool
///   default: true      # inferred true when both required and optional are absent
///
/// optional:
///   type: Bool
///   default: false
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
/// ```
public struct ManagedPreferences: Equatable {

    // MARK: Properties

    /// Short app names to target. Empty means all installed apps.
    public let apps: [ConcreteApp]

    /// Include required content packages.
    public let required: Bool

    /// Include optional content packages.
    public let optional: Bool

    /// Force deploy regardless of existing install state.
    public let forceDeploy: Bool

    /// Skip pkgutil signature check on downloaded packages.
    public let skipSignatureCheck: Bool

    /// Minimum log level.
    public let logLevel: AppLogLevel

    /// Cache server to use. `.auto` means attempt discovery; `nil` means no caching server
    /// was requested (should not occur under managed defaults — see `ManagedPreferencesReader`).
    public let cacheServer: CacheServer?

    /// Mirror server base URL. When non-nil, takes precedence over `cacheServer`.
    public let mirrorServer: MirrorServer?

    /// Dry run flag. May be overridden to `true` by the `--dry-run` CLI flag.
    public let dryRun: Bool

    /// Suppress all console output.
    public let quietRun: Bool
}
