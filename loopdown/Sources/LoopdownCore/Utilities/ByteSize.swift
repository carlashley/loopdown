//// ByteSize.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation


// MARK: - Byte Size utility
/// Represents a byte size value with human-readable formatting.
public struct ByteSize: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let raw: Int64

    public init(_ raw: Int64) {
        self.raw = raw
    }

    /// Human readable size using 1024-based units with decimal suffixes:
    /// B, KB, MB, GB, TB, PB (not KiB/MiB).
    public var human: String {
        var v = Double(raw)
        var idx = 0
        let suffixes = ["B", "KB", "MB", "GB", "TB", "PB"]
        let blockSize = 1024.0

        while v >= blockSize && idx < suffixes.count - 1 {
            v /= blockSize
            idx += 1
        }

        return String(format: "%.2f%@", v, suffixes[idx])
    }

    // Default text representation for logging/interpolation
    public var description: String {
        human
    }
    
    public static func < (lhs: ByteSize, rhs: ByteSize) -> Bool {
        lhs.raw < rhs.raw
    }
}
