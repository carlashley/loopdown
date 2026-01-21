import logging
import plistlib

from dataclasses import dataclass, field
from datetime import datetime
from functools import cached_property
from pathlib import Path
from typing import Optional

from ..consts.apple_enums import ApplicationConsts, _NAME_MAPPING
from ..utils.path_utils import rglob_plist

log = logging.getLogger(__name__)


@dataclass
class Application:
    """Installed audio application, such as GarageBand, Logic Pro, and/or MainStage."""

    name: str
    version: str
    path: Path
    last_modified: datetime
    short_name: Optional[str] = field(default=None)

    def __post_init__(self) -> None:
        """Normalize fields after init to expected data types and set empty attributes when we have data."""
        self.path = Path(self.path)
        self.short_name = self._get_short_name()

        if isinstance(self.last_modified, str):
            self.last_modified = datetime.strptime(self.last_modified, "%Y-%m-%dT%H:%M:%SZ")

    @cached_property
    def packages(self) -> Optional[dict]:
        """Packages metadata from the resource file."""
        return self._read_metadata_source_file()

    def _get_short_name(self) -> Optional[str]:
        """App short name."""
        for sn, real_names in _NAME_MAPPING.items():
            if self.name.casefold() in real_names:
                return sn

        return None

    def _find_resource_file(self) -> Optional[Path]:
        """Find the relevant property list resource file containing package metadata."""
        resource_fp = self.path.joinpath(ApplicationConsts.RESOURCE_FILE_PATH)
        resource_file: Optional[Path] = None

        # for fp in resource_fp.rglob("*.plist"):
        for fp in rglob_plist(resource_fp):
            if not ApplicationConsts.META_FILE_PATTERN.match(fp.name):
                continue

            if not any(name in fp.name for name in ApplicationConsts.SHORT_NAMES):
                continue

            if resource_file is None or fp.name > resource_file.name:
                resource_file = fp

        log.debug(f"Found application resource file {str(resource_file)!r}")
        return resource_file

    def _read_metadata_source_file(self, *, mode: str = "rb") -> Optional[dict]:
        """Read the metadata source file.
        :param mode: read mode; default is 'rb'"""
        resource_file = self._find_resource_file()

        if resource_file is None:
            return None

        with resource_file.open(mode) as f:
            try:
                data = plistlib.load(f)
            except Exception as e:
                log.error(f"Unable to parse packages from '{str(resource_file)}': {e}")
                return None

        return data.get("Packages", None)
