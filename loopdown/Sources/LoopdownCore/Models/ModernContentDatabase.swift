//// ModernContentDatabase.swift
// loopdown
//
// Created on 12/4/2026
//

import Foundation


// MARK: - ModernContentDatabase

/// Reads package metadata from the SQLite content database used by Logic Pro 12+ and MainStage 4+.
///
/// The database is located at:
///   `<app>/Contents/Resources/Library.bundle/ContentDatabaseV01.db/index.db`
///
/// Mirrors the behaviour of the Python `PackageDatabase` class in `models/sqlitedb.py`.
public enum ModernContentDatabase {

    // MARK: - CTE query

    /// CTE query that selects all packages from the content database.
    ///
    /// Notes:
    /// - The query returns all rows; `minimum_app_version` filtering is done in Swift
    ///   after parsing (rows with a NULL `minimum_app_version` are included unconditionally).
    /// - The `ZMINIMUMAPPVERSION` column contains a string like
    ///   `[logic.macOS:1.0][mainstage.macOS:1.0][logic.iOS:9999.9999]`. Apple uses `9999`
    ///   as a sentinel meaning "not available for this platform/app". The query renames
    ///   `logic` → `logicpro` so short names match our internal naming convention.
    /// - `is_essential = 1` for `ecp*` identifiers (Essential Content Packages).
    /// - `is_core      = 1` for `ccp*` identifiers (Core Content Packages).
    /// - `is_optional  = 1` for everything else.
    private static let cteQuery = """
        WITH packages AS (
            SELECT
                p.Z_PK                  AS id,
                p.ZDISPLAYNAME          AS name,
                p.ZIDENTIFIER           AS package_id,
                CASE WHEN p.ZIDENTIFIER LIKE 'ecp%' THEN 1 ELSE 0 END AS is_essential,
                CASE WHEN p.ZIDENTIFIER LIKE 'ccp%' THEN 1 ELSE 0 END AS is_core,
                CASE WHEN p.ZIDENTIFIER NOT LIKE 'ecp%'
                      AND p.ZIDENTIFIER NOT LIKE 'ccp%' THEN 1 ELSE 0 END AS is_optional,
                p.ZDOWNLOADSIZE         AS download_size,
                p.ZINSTALLEDSIZE        AS installed_size,
                p.ZINSTALLEDVERSION     AS installed_local_version,
                p.ZSERVERVERSION        AS server_version,
                p.ZSERVERPATH           AS server_path,
                p.ZSERVERPATH           AS download_name,
                p.ZINSTALLEDDATE        AS installed_date,
                REPLACE(p.ZMINIMUMAPPVERSION, 'logic', 'logicpro') AS minimum_app_version,
                COUNT(i.Z_PK)           AS total_item_count,
                SUM(CASE WHEN (i.ZFILETYPE >> 16) != 2 THEN 1 ELSE 0 END)
                                        AS logic_item_count,
                p.ZMINIMUMSOCVERSION    AS minimum_soc_version,
                p.ZINAPPPACKAGE         AS in_app_package,
                p.ZVISIBLEINSTOREFRONT  AS in_store_front,
                0 AS is_legacy,
                CASE
                    WHEN p.ZIDENTIFIER LIKE 'ccp%' THEN 'Core Content'
                    WHEN p.ZIDENTIFIER LIKE 'ecp%' THEN 'Essential Content'
                    WHEN p.ZIDENTIFIER LIKE 'apc%' THEN 'Artist/Producer Pack'
                    WHEN p.ZIDENTIFIER LIKE 'arx%' THEN 'Artist/Remix'
                    ELSE                                 'Sound Pack'
                END                     AS category
            FROM ZPACKAGE p
            LEFT JOIN Z_3PACKAGES lp ON lp.Z_4PACKAGES = p.Z_PK
            LEFT JOIN ZITEM i        ON i.Z_PK = lp.Z_3ITEMS1
            GROUP BY p.Z_PK
        )
        SELECT *
        FROM packages
        ORDER BY category, name;
        """


    // MARK: - ZMINIMUMAPPVERSION parsing

    /// Parse the `ZMINIMUMAPPVERSION` column value into a `[shortName: majorVersion]` dictionary,
    /// keeping only macOS entries and excluding the `9999` sentinel.
    ///
    /// Example input (after CTE renames `logic` → `logicpro`):
    ///   `"[logicpro.macOS:1.0][mainstage.macOS:1.0][logicpro.iOS:9999.9999]"`
    /// Result: `["logicpro": 1.0, "mainstage": 1.0]`
    ///
    /// Mirrors the Python `parse_macos_versions` function.
    static func parseMinimumAppVersions(_ value: String) -> [String: Double] {
        let pattern = #"\[(\w+)\.(\w+):([^\]]+)\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }

        let ns = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: ns.length))
        var result: [String: Double] = [:]

        for match in matches {
            guard match.numberOfRanges == 4 else { continue }
            let appName  = ns.substring(with: match.range(at: 1))
            let platform = ns.substring(with: match.range(at: 2))
            let verStr   = ns.substring(with: match.range(at: 3))
            guard platform == "macOS", let version = Double(verStr), version < 9999 else { continue }
            result[appName] = version
        }

        return result
    }


    // MARK: - Public query

    /// Query the content database and return all applicable packages.
    ///
    /// All rows are returned from the database. Post-filtering:
    /// - Rows with a NULL `minimum_app_version` are included unconditionally.
    /// - Rows with a non-NULL `minimum_app_version` are included only if the parsed
    ///   version map contains at least one valid macOS entry (i.e. not all 9999).
    ///
    /// - Parameters:
    ///   - databaseURL: URL of the `index.db` SQLite file inside the application bundle.
    ///   - logger: Logger for debug output.
    /// - Returns: Array of row dictionaries. Empty on any database error.
    public static func allContent(
        databaseURL: URL,
        logger: CoreLogger = NullLogger()
    ) -> [[String: SQLiteValue]] {
        let db: SQLiteDatabase

        do {
            db = try SQLiteDatabase(url: databaseURL)
        } catch {
            logger.debug("ModernContentDatabase: failed to open '\(databaseURL.path)': \(error)")
            return []
        }

        defer { db.close() }

        let rows: [[String: SQLiteValue]]

        do {
            rows = try db.query(cteQuery)
        } catch {
            logger.debug("ModernContentDatabase: query failed: \(error)")
            return []
        }

        // Post-filter: if minimum_app_version is present it must parse to at least one
        // valid macOS entry. NULL minimum_app_version rows are always included.
        return rows.filter { row in
            guard let minVerStr = row["minimum_app_version"]?.stringValue,
                  !minVerStr.isEmpty
            else {
                // NULL or empty → no restriction → include
                return true
            }
            let versions = parseMinimumAppVersions(minVerStr)
            return !versions.isEmpty
        }
    }
}
