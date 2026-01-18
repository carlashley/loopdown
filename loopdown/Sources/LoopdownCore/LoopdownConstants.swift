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

    public enum Apps {
        public static let resourceFilePath = "Contents/Resources"

        public static let metaFileRegex: NSRegularExpression = {
            let pattern = #"^[A-Za-z]+[0-9]+\.plist$"#
            return try! NSRegularExpression(pattern: pattern)
        }()
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
