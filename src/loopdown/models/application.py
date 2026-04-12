"""Application model."""

import logging
import plistlib

from collections.abc import Iterator
from dataclasses import dataclass, field
from functools import cached_property
from os import scandir, fspath
from pathlib import Path
from typing import Any, Optional

from .._config import ApplicationConsts as Consts
from .sqlitedb import PackageDatabase, SQLiteReader

log = logging.getLogger(__name__)

DATACLASS_ATTRS_MAP: dict[str, str] = {
    "_name": "name",
    "version": "version",
    "path": "path",
}

DB_PATH: Path = Path("Contents/Resources/Library.bundle/ContentDatabaseV01.db/index.db")
MODERN_APPS_VERS: dict[str, int] = {"logicpro": 12, "mainstage": 4}


def get_app_shortname(fn: str) -> Optional[str]:
    """Get the 'shortname' (i.e. garageband, logicpro, mainstage) from the actual application name.
    :param fn: full application name; for example 'Garage Band'."""
    return next(
        (shortname for shortname, realnames in Consts.NAME_MAPPING.items() if fn.casefold() in realnames), None
    )


def rglob_plist(root: str | Path) -> Iterator[Path]:
    """Yield '.plist' files under a root path using 'os.scandir'.
    :param root: path string to glob"""
    # this is faster than 'Path.rglob'
    try:
        with scandir(fspath(root)) as it:
            for entry in it:
                try:
                    if entry.is_dir(follow_symlinks=False):
                        yield from rglob_plist(entry.path)
                    elif entry.is_file(follow_symlinks=False) and entry.name.endswith(".plist"):
                        yield Path(entry.path)
                except PermissionError:
                    continue
    except (FileNotFoundError, NotADirectoryError):
        pass


def find_meta_file(app_path: Path) -> Optional[Path]:
    """Find the relevant property list resource file that contains package metadata. Relies on the naming pattern
    'appshortnameVERSION.plist'; for example 'garageband1012.plist'
    :param app_path: application path object"""
    globdir = app_path.joinpath(Consts.RESOURCE_FILE_PATH)
    meta_file: Optional[Path] = None

    for fp in rglob_plist(globdir):
        if not Consts.META_FILE_PATTERN.match(fp.name) or not any(name in fp.name for name in Consts.SHORT_NAMES):
            continue

        if meta_file is None or fp.name > meta_file.name:
            meta_file = fp

    return meta_file


def read_meta_file(fp: Path, *, mode: str = "rb") -> Optional[dict[str, Any]]:
    """Read the file containing metadata.
    :param fp: meta file as Path object
    :param mode: file operation mode; default is 'rb' (read-binary mode)"""
    with fp.open(mode) as f:
        try:
            data = plistlib.load(f)
        except Exception as e:
            log.error("Unable to read metadata from '%s': %s", str(fp), str(e))
            return None

    metadata = data.get("Packages")
    log.debug("Metadata from '%s' found", str(fp))
    return metadata


@dataclass
class Application:
    """Installed audio application, such as GarageBand, Logic Pro, and/or MainStage."""

    name: str
    version: str
    path: Path
    short_name: Optional[str] = field(default=None)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Optional["Application"]:
        """Emits an instance of 'Application' from mapping data.
        :param data: raw mapping of application keys to values"""
        values = {mapped_attr: data.get(attr) for attr, mapped_attr in DATACLASS_ATTRS_MAP.items()}

        try:
            return cls(**values)
        except Exception as e:
            log.error("Failed to create %s from data: %s", cls.__name__, str(e))
            return None

    def __post_init__(self) -> None:
        """Normalize fields after init to expected data types and update empty attributes once we have data."""
        self.path = Path(self.path)
        self.short_name = get_app_shortname(self.name)

    def __str__(self) -> str:
        """Custom string representation."""
        return f"{self.name} version {self.version} at {str(self.path)}"

    @property
    def content_db(self) -> SQLiteReader:
        """Content database for apps that have a modernised database derived package construct."""
        if self.is_modernised:
            return SQLiteReader(db=self.path.joinpath(DB_PATH))

    @property
    def is_modernised(self) -> bool:
        """Indicates the application has the modernised content deployment method."""
        return self.short_name in MODERN_APPS_VERS and self.major_version >= MODERN_APPS_VERS[self.short_name]

    @cached_property
    def major_version(self) -> int:
        """The major version number of the app."""
        return int(self.version.split(".")[0])

    @cached_property
    def packages(self) -> Optional[dict[str, Any]]:
        """Packages metadata from the resource file."""
        if self.is_modernised and self.short_name is not None:
            db = PackageDatabase(self.content_db)
            return db.all_content(self.short_name)

        meta_file = find_meta_file(self.path)
        return read_meta_file(meta_file) if meta_file is not None else None
