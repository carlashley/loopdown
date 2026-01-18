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
        public static let realNames: Set<String> = {
            var s = Set<String>()
            for realList in nameMapping.values {
                for real in realList {
                    s.insert(normalizeName(real))
                }
            }
            return s
        }()
        
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
        }
    }

    public enum Identifiers {
        public static let defaultSubsystem = "com.github.carlashley.loopdown"
    }
    
    public enum Logging {
        /// Where loopdown writes logs (old project used /Users/Shared/loopdown).
        public static let logDirectoryURL = URL(fileURLWithPath: "/Users/Shared/loopdown", isDirectory: true)
    }
    
    public enum Paths {
        /// Default destination for downloaded/staged content.
        public static let defaultDest = "/tmp/loopdown"
    }

}
