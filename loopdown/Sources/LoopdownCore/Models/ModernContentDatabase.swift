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

    /// Parameterised CTE query that selects all packages applicable to `appShortName`.
    ///
    /// The `?` placeholder is bound to the app short name (e.g. `"logicpro"` or `"mainstage"`).
    ///
    /// Notes:
    /// - Apple uses `9999.9999` as a sentinel value meaning "available to any app version".
    ///   Rows where the macOS version for the target app is `9999` are excluded.
    /// - The `ZMINIMUMAPPVERSION` column contains a string like
    ///   `[logic.macOS:1.0][mainstage.macOS:1.0][logic.iOS:9999.9999]`. The query renames
    ///   `logic` → `logicpro` so short names match our internal naming convention throughout.
    /// - `mandatory = 1` when the identifier starts with `ccp` (Core Content Package) or
    ///   `ecp` (Essential Content Package).
    private static let cteQuery = """
        WITH packages AS (
            SELECT
                p.Z_PK                  AS id,
                p.ZDISPLAYNAME          AS name,
                p.ZIDENTIFIER           AS package_id,
                CASE
                    WHEN p.ZIDENTIFIER LIKE 'ccp%' THEN 1
                    WHEN p.ZIDENTIFIER LIKE 'ecp%' THEN 1
                    ELSE                                 0
                END                     AS mandatory,
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
            WHERE (
                p.ZMINIMUMAPPVERSION IS NULL
                OR p.ZMINIMUMAPPVERSION NOT LIKE '%[logicpro.macOS:9999%'
                OR p.ZMINIMUMAPPVERSION NOT LIKE '%[mainstage.macOS:9999%'
            )
            GROUP BY p.Z_PK
        )
        SELECT *
        FROM packages
        WHERE minimum_app_version LIKE '%' || ? || '%'
        ORDER BY category, name;
        """


    // MARK: - ZMINIMUMAPPVERSION parsing

    /// Parse the `ZMINIMUMAPPVERSION` column value into a `[shortName: majorVersion]` dictionary,
    /// keeping only macOS entries and excluding the `9999` sentinel.
    ///
    /// Example input: `"[logic.macOS:1.0][mainstage.macOS:1.0][logic.iOS:9999.9999]"`
    /// After the CTE renames `logic` → `logicpro`:
    ///   `"[logicpro.macOS:1.0][mainstage.macOS:1.0][logicpro.iOS:9999.9999]"`
    /// Result: `["logicpro": 1.0, "mainstage": 1.0]`
    ///
    /// Mirrors the Python `parse_macos_versions` function.
    static func parseMinimumAppVersions(_ value: String) -> [String: Double] {
        // Pattern: [appName.platform:version]
        // Captures: (appName, platform, version)
        let pattern = #"\[(\w+)\.(\w+):([^\]]+)\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }

        let ns = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: ns.length))

        var result: [String: Double] = [:]

        for match in matches {
            guard match.numberOfRanges == 4 else { continue }

            let appName  = ns.substring(with: match.range(at: 1))
            let platform = ns.substring(with: match.range(at: 2))
            let verStr   = ns.substring(with: match.range(at: 3))

            guard platform == "macOS",
                  let version = Double(verStr),
                  version < 9999
            else { continue }

            result[appName] = version
        }

        return result
    }


    // MARK: - Public query

    /// Query the content database and return all applicable packages for `appShortName`.
    ///
    /// - Parameters:
    ///   - databaseURL: URL of the `index.db` SQLite file inside the application bundle.
    ///   - appShortName: Internal short name of the app: `"logicpro"` or `"mainstage"`.
    ///   - logger: Logger for debug output.
    ///
    /// - Returns: Array of row dictionaries (column name → `SQLiteValue`) for rows where the
    ///   `minimum_app_version` map contains an entry for `appShortName` with a valid macOS
    ///   version. Returns an empty array on any database error.
    public static func allContent(
        databaseURL: URL,
        appShortName: String,
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
            rows = try db.query(cteQuery, params: [appShortName])
        } catch {
            logger.debug("ModernContentDatabase: query failed: \(error)")
            return []
        }

        // Post-filter: parse minimum_app_version and confirm the app is actually listed
        // (the LIKE '%appShortName%' in the CTE can match substrings; this is the exact check).
        return rows.filter { row in
            guard let minVerStr = row["minimum_app_version"]?.stringValue else {
                // NULL minimum_app_version → no restriction → include
                return true
            }
            let versions = parseMinimumAppVersions(minVerStr)
            return versions[appShortName] != nil
        }
    }
}
