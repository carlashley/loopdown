//// SQLiteDatabase.swift
// loopdown
//
// Created on 12/4/2026
//

import Foundation
import SQLite3


// MARK: - SQLiteDatabase

/// Thin wrapper around the SQLite3 C API for read-only query access.
///
/// Mirrors the behaviour of the Python `SQLiteReader` class. Open with
/// `SQLiteDatabase(url:)`, run parameterised queries with `query(_:params:)`,
/// and close explicitly or allow `deinit` to close automatically.
///
/// All operations are synchronous and intended to be called from a background
/// context (e.g. inside a `Task` or `DispatchQueue`).
public final class SQLiteDatabase {

    // MARK: - Errors

    public enum SQLiteError: Error, CustomStringConvertible {
        case databaseNotFound(URL)
        case openFailed(URL, String)
        case prepareFailed(String, String)
        case stepFailed(String)
        case bindFailed(Int, String)

        public var description: String {
            switch self {
            case .databaseNotFound(let url):
                return "SQLite database not found: '\(url.path)'"
            case .openFailed(let url, let msg):
                return "Failed to open SQLite database '\(url.path)': \(msg)"
            case .prepareFailed(let sql, let msg):
                return "Failed to prepare statement '\(sql.prefix(80))': \(msg)"
            case .stepFailed(let msg):
                return "Failed to step statement: \(msg)"
            case .bindFailed(let idx, let msg):
                return "Failed to bind parameter at index \(idx): \(msg)"
            }
        }
    }


    // MARK: - Private state

    private var db: OpaquePointer?
    private let url: URL


    // MARK: - Init / deinit

    /// Open the SQLite database at `url` in read-only mode.
    ///
    /// - Throws: `SQLiteError.databaseNotFound` if the file does not exist,
    ///           `SQLiteError.openFailed` if `sqlite3_open_v2` fails.
    public init(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SQLiteError.databaseNotFound(url)
        }

        self.url = url

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(url.path, &db, flags, nil)

        guard rc == SQLITE_OK, let _ = db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw SQLiteError.openFailed(url, msg)
        }
    }

    deinit {
        close()
    }


    // MARK: - Close

    public func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }


    // MARK: - Query

    /// Execute a parameterised `SELECT` query and return all rows as `[[String: SQLiteValue]]`.
    ///
    /// - Parameters:
    ///   - sql: The SQL string. Use `?` placeholders for parameters.
    ///   - params: Text values bound positionally to each `?` placeholder.
    /// - Returns: Array of row dictionaries keyed by column name.
    /// - Throws: `SQLiteError` on prepare/bind/step failures.
    public func query(_ sql: String, params: [String] = []) throws -> [[String: SQLiteValue]] {
        guard let db else {
            throw SQLiteError.openFailed(url, "database is closed")
        }

        var stmt: OpaquePointer?

        let prepRC = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepRC == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepareFailed(sql, msg)
        }

        defer { sqlite3_finalize(stmt) }

        // Bind text parameters (all params are bound as text; SQLite will coerce as needed).
        // SQLITE_TRANSIENT (-1) tells SQLite to copy the string immediately.
        // The macro cannot be imported directly into Swift; use the raw value cast instead.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)   // SQLite bind indices are 1-based
            let rc = sqlite3_bind_text(stmt, idx, param, -1, transient)
            if rc != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw SQLiteError.bindFailed(Int(idx), msg)
            }
        }

        var rows: [[String: SQLiteValue]] = []
        let columnCount = sqlite3_column_count(stmt)

        while true {
            let stepRC = sqlite3_step(stmt)

            if stepRC == SQLITE_DONE { break }

            if stepRC != SQLITE_ROW {
                let msg = String(cString: sqlite3_errmsg(db))
                throw SQLiteError.stepFailed(msg)
            }

            var row: [String: SQLiteValue] = [:]

            for col in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(stmt, col))
                let type = sqlite3_column_type(stmt, col)

                switch type {
                case SQLITE_INTEGER:
                    row[name] = .integer(sqlite3_column_int64(stmt, col))
                case SQLITE_FLOAT:
                    row[name] = .real(sqlite3_column_double(stmt, col))
                case SQLITE_TEXT:
                    let text = sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
                    row[name] = .text(text)
                case SQLITE_NULL:
                    row[name] = .null
                default:
                    // SQLITE_BLOB — treat as null for our purposes (no blob columns in this schema)
                    row[name] = .null
                }
            }

            rows.append(row)
        }

        return rows
    }
}


// MARK: - SQLiteValue

/// A typed SQLite column value.
public enum SQLiteValue: Sendable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case null

    // MARK: - Convenience accessors

    public var intValue: Int64? {
        if case .integer(let v) = self { return v }
        if case .real(let v) = self { return Int64(v) }
        return nil
    }

    public var doubleValue: Double? {
        if case .real(let v) = self { return v }
        if case .integer(let v) = self { return Double(v) }
        return nil
    }

    public var stringValue: String? {
        if case .text(let v) = self { return v }
        return nil
    }

    public var boolValue: Bool {
        if case .integer(let v) = self { return v != 0 }
        return false
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}
