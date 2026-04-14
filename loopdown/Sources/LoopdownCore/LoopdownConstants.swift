//// LoopdownConstants.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation

/// Shared constants for the loopdown tool.
///
/// This is *namespace* only. Prefer nesting constants by domain to avoid a grab-bag file.
public enum LoopdownConstants {

    public enum Applications {
        public static let resourceFilePath = "Contents/Resources"

        /// Matches the resource plist naming pattern like 'garageband1024.plist'.
        public static let metaFileRegex: NSRegularExpression = {
            let pattern = #"^[A-Za-z]+[0-9]+\.plist$"#
            return try! NSRegularExpression(pattern: pattern)
        }()
        
        /// Map internal short names to acceptable application bundle display names (preference order).
        public static let nameMapping: [String: [String]] = [
            "garageband": ["garageband"],
            "logicpro": ["logic pro", "logic pro x"],
            "mainstage": ["mainstage"]
        ]
        
        /// Valid short names (CLI/internal).
        public static let shortNames: [String] = Array(nameMapping.keys).sorted()
        
        /// All acceptable real names (normalized) for quick membership checks.
        public static let realNames: Set<String> = Set(
            nameMapping.values.joined().map { normalizeName($0) }
        )
        
        /// Stable locale for name normalization (avoid Turkish-i etc),
        private static let nameLocale = Locale(identifier: "en_US_POSIX")
        
        /// Normalize a name for matching; similar to Python `.casefold()`
        public static func normalizeName(_ s: String) -> String {
            s.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: nameLocale
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        /// Resolve short name for a given real app name (or nil if not supported)
        public static func shortName(for realName: String) -> String? {
            let needle = normalizeName(realName)
            for (short, realNames) in nameMapping {
                if realNames.contains(where: { normalizeName($0) == needle }) {
                    return short
                }
            }
            return nil
        }
    }
    
    public enum Downloads {
        public static let contentSourceBaseURL = URL(string: "https://audiocontentdownload.apple.com")!

        public enum ContentPaths {
            public static let path2013 = "lp10_ms3_content_2013"
            public static let path2016 = "lp10_ms3_content_2016"

            /// Path prefix prepended to `ZSERVERPATH` values from the modern SQLite
            /// content database. This prefix is baked into `downloadPath` on modern
            /// packages so that the server (Apple CDN, cache, or mirror) can be
            /// prepended uniformly without any per-package branching.
            ///
            /// Mirrors `ServerBases.MODERN = "universal/ContentPacks_3"` in Python.
            public static let modernPrefix = "universal/ContentPacks_3"
        }
    }

    public enum ModernApps {
        /// Minimum major version at which an app switches to the modern SQLite-based
        /// content delivery system. Apps not listed here (i.e. GarageBand) are always legacy.
        public static let minimumModernVersion: [String: Int] = [
            "logicpro":  12,
            "mainstage":  4,
        ]

        /// Relative path inside the `.app` bundle to the SQLite content database.
        public static let contentDatabaseRelativePath =
            "Contents/Resources/Library.bundle/ContentDatabaseV01.db/index.db"

        /// Fixed name of the library bundle created inside the parent directory.
        public static let libraryBundleName = "Logic Pro Library.bundle"

        /// Default parent directory under which the library bundle is created.
        public static let defaultLibraryDestParent = "/Users/Shared"

        /// Full default path to the library bundle (parent + bundle name).
        /// Retained for any callers that need the complete path directly.
        public static let defaultLibraryDestPath =
            defaultLibraryDestParent + "/" + libraryBundleName
    }

    public enum Identifiers {
        public static let defaultSubsystem = "com.github.carlashley.loopdown"
    }
    
    public enum Paths {
        /// Default destination for downloaded/staged content.
        public static let defaultDest = "/tmp/loopdown"
    }

}
