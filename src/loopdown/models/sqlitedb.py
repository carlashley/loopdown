import sqlite3
import re

from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Self

VERSION_PTN = re.compile(r"\[(\w+)\.(\w+):([^\]]+)\]")


def parse_macos_versions(vers: str) -> dict[str, float]:
    """Parses a 'ZMINIMUMAPPVERSION' string like '[logic.macOS:1.0][mainstage.macOS:1.0][logic.iOS:9999.9999]' into
    a dictionary like '{"logic": 1.0, "mainstage": 1.0}'
    :param vers: version string from 'ZMINIMUMAPPVERSION' column"""
    return {
        app: float(ver)
        for m in VERSION_PTN.finditer(vers)
        for app, platform, ver in (m.groups(),)
        if platform == "macOS" and float(ver) < 9999
    }


@dataclass
class SQLiteReader:
    """Implements an SQLite DB reader."""

    db: Path
    connection: sqlite3.Connection | None = field(default=None, init=False, repr=False)
    cursor: sqlite3.Cursor | None = field(default=None, init=False, repr=False)

    def __post_init__(self) -> None:
        if not self.db.exists():
            raise FileNotFoundError(f"Database not found: '{str(self.db)}'")

        self.connection = sqlite3.connect(self.db)
        self.connection.row_factory = sqlite3.Row

    def __enter__(self) -> Self:
        """Return self on entrance."""
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """Calls the close method on exit."""
        self.close()

    def close(self) -> None:
        """Close method."""
        if self.connection:
            self.connection.close()
            self.connection = None
            self.cursor = None

    def select(self, q: str, *, params: tuple[Any, ...] | None = None) -> Self:
        """Execute a query string.
        :param q: query string
        :param params: optional tuple of parameters"""
        assert self.connection, "Connection is closed"

        self.cursor = self.connection.execute(q, params or ())

        return self

    def next(self) -> sqlite3.Row | None:
        """Get next record."""
        assert self.cursor, "Call select() first"
        return self.cursor.fetchone()

    def all(self) -> list[sqlite3.Row]:
        """Get all records."""
        assert self.cursor, "Call select() first"
        return self.cursor.fetchall()

    def __iter__(self) -> Iterator[sqlite3.Row]:
        """Iterator."""
        assert self.cursor, "Call select() first"
        yield from self.cursor


@dataclass
class PackageDatabase:
    db: SQLiteReader

    # cte query for simpler selection; note, appears Apple uses '9999.9999' as a sentinal
    # value to say available to any version app.
    # the 'ZMINIMUMAPPVERSION' value is something like '[logic.macOS:1.0][mainstage.macOS:1.0][logic.iOS:9999.9999]'
    # which flags the package is available for logic+mainstage on macOS (any version > 1), but not logic on iOS;
    # we're also renaming 'logic' strings in 'ZMINIMUMAPPVERSION' columns to 'logicpro' so we can effectively use
    # our own shortname 'logicpro'
    cte_query: str = """
WITH packages AS (
    SELECT
        p.Z_PK                  AS id,
        p.ZDISPLAYNAME          AS name,
        p.ZIDENTIFIER           AS package_id,
        CASE WHEN p.ZIDENTIFIER LIKE 'ecp%' THEN 1 ELSE 0 END AS is_essential,
        CASE WHEN p.ZIDENTIFIER LIKE 'ccp%' THEN 1 ELSE 0 END AS is_core,
        CASE WHEN p.ZIDENTIFIER NOT LIKE 'ecp%' AND p.ZIDENTIFIER NOT LIKE 'ccp%' THEN 1 ELSE 0 END AS is_optional,
        p.ZDOWNLOADSIZE         AS download_size,
        p.ZINSTALLEDSIZE        AS installed_size,
        p.ZINSTALLEDVERSION     AS installed_local_version,
        p.ZSERVERVERSION        AS server_version,
        p.ZSERVERPATH           AS server_path,
        p.ZSERVERPATH           AS download_name,
        p.ZINSTALLEDDATE        AS installed_date,
        REPLACE(p.ZMINIMUMAPPVERSION, 'logic', 'logicpro')    AS minimum_app_version,
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
ORDER BY category, name;
    """

    def all_content(self) -> dict[str, dict[str, Any]]:
        """Get all packages for Logic Pro and MainStage for macOS."""
        # not all rows have a minimum app version, so presume if absent they're valid packs for macOS use
        out: dict[str, dict[str, Any]] = {}

        with self.db as db:
            records = db.select(self.cte_query).all()

            for _ in records:
                row = dict(_)

                if row.get("minimum_app_version"):
                    row["minimum_app_version"] = parse_macos_versions(row["minimum_app_version"])

                out[row["package_id"]] = row

        return out
