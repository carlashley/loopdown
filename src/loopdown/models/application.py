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

log = logging.getLogger(__name__)

DATACLASS_ATTRS_MAP: dict[str, str] = {
    "_name": "name",
    "version": "version",
    "path": "path",
}


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
    def from_dict(cls, data: dict[str, Any]) -> "Application":
        """Emits an instance of 'Application' from mapping data.
        :param data: raw mapping of application keys to values"""
        values = {mapped_attr: data.get(attr) for attr, mapped_attr in DATACLASS_ATTRS_MAP.items()}
        return cls(**values)

    def __post_init__(self) -> None:
        """Normalize fields after init to expected data types and update empty attributes once we have data."""
        self.path = Path(self.path)
        self.short_name = get_app_shortname(self.name)

    def __str__(self) -> str:
        """Custom string representation."""
        return f"{self.name} version {self.version} at {str(self.path)}"

    @cached_property
    def packages(self) -> Optional[dict[str, Any]]:
        """Packages metadata from the resource file."""
        meta_file = find_meta_file(self.path)
        return read_meta_file(meta_file) if meta_file is not None else None
