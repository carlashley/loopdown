//// AudioContentPackage.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation


// MARK: - AudioContentPackage model
/// Audio content package metadata decoded from Apple application resource plists.
///
/// Note:
/// - Hashing and equality are intentionally based only on `packageID`.
public struct AudioContentPackage: Hashable, Decodable, CustomStringConvertible {

    // MARK: - Stored properties

    public var downloadName: String
    public var packageID: String                      // Identity field
    public var downloadSize: ByteSize
    public var fileCheck: [String]                    // Decodes from String or [String]
    public var installedSize: ByteSize
    public var mandatory: Bool
    public var version: String?

    // MARK: - Derived properties

    public var name: String {
        URL(fileURLWithPath: downloadName).lastPathComponent
    }

    /// Normalized relative path for use on Apple CDN / mirror.
    public var downloadPath: String {
        PackagePathNormalizer.normalizePackageDownloadPath(downloadName)
    }

    public var description: String { name }


    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case downloadName = "DownloadName"
        case packageID = "PackageID"
        case downloadSize = "DownloadSize"
        case fileCheck = "FileCheck"
        case installedSize = "InstalledSize"
        case mandatory = "IsMandatory"        // may be missing
        case version = "PackageVersion"      // may be String or Number
    }

    /// Allow decoding `fileCheck` from either `"foo"` or `["foo", "bar"]` into `[String]`.
    private enum StringOrStringArray: Decodable {
        case string(String)
        case array([String])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()

            if let s = try? c.decode(String.self) {
                self = .string(s)
                return
            }
            if let a = try? c.decode([String].self) {
                self = .array(a)
                return
            }

            throw DecodingError.typeMismatch(
                StringOrStringArray.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected 'FileCheck' to be a String or [String]"
                )
            )
        }

        var normalized: [String] {
            switch self {
            case .string(let s):
                return s.isEmpty ? [] : [s]
            case .array(let a):
                return a
            }
        }
    }

    /// Allow decoding `PackageVersion` that may be a String or a Number into a String.
    private enum StringOrNumber: Decodable {
        case string(String)
        case int(Int)
        case int64(Int64)
        case double(Double)

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()

            if let s = try? c.decode(String.self) { self = .string(s); return }
            if let i = try? c.decode(Int.self) { self = .int(i); return }
            if let i64 = try? c.decode(Int64.self) { self = .int64(i64); return }
            if let d = try? c.decode(Double.self) { self = .double(d); return }

            throw DecodingError.typeMismatch(
                StringOrNumber.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Number")
            )
        }

        var stringValue: String {
            switch self {
            case .string(let s):
                return s
            case .int(let i):
                return String(i)
            case .int64(let i):
                return String(i)
            case .double(let d):
                // avoid "12.0" if it's an integer-valued double
                if d.rounded(.towardZero) == d {
                    return String(Int64(d))
                }
                return String(d)
            }
        }
    }


    // MARK: - Decodable init (normalization)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let rawDownloadName = try c.decode(String.self, forKey: .downloadName)
        let rawPackageID = try c.decode(String.self, forKey: .packageID)

        let rawDownloadSize = try c.decodeIfPresent(Int64.self, forKey: .downloadSize) ?? 0
        let rawInstalledSize = try c.decodeIfPresent(Int64.self, forKey: .installedSize) ?? 0
        let rawMandatory = try c.decodeIfPresent(Bool.self, forKey: .mandatory) ?? false
        let rawVersion = try c.decodeIfPresent(StringOrNumber.self, forKey: .version)?.stringValue

        let rawFileCheck: [String]
        if let mixed = try c.decodeIfPresent(StringOrStringArray.self, forKey: .fileCheck) {
            rawFileCheck = mixed.normalized
        } else {
            rawFileCheck = []
        }

        self.packageID = rawPackageID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.downloadName = rawDownloadName
        self.downloadSize = ByteSize(rawDownloadSize)
        self.fileCheck = rawFileCheck
        self.installedSize = ByteSize(rawInstalledSize)
        self.mandatory = rawMandatory
        self.version = rawVersion
    }


    // MARK: - Hashable / Equatable (identity by packageID only)

    public func hash(into hasher: inout Hasher) {
        hasher.combine(packageID)
    }

    public static func == (lhs: AudioContentPackage, rhs: AudioContentPackage) -> Bool {
        lhs.packageID == rhs.packageID
    }
}
