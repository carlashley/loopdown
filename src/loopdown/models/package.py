from dataclasses import dataclass, field
from functools import partial
from pathlib import Path
from typing import Optional

from packaging import version as vers
from .json_mixin import AsJsonMixin
from .size import Size
from ..utils.normalizers import normalize_file_check_value, normalize_package_download_path
from ..utils.package_utils import (
    found_sentinel_files,
    installed_pkg_version,
    installed_version_satisfies_required_version,
)

nohash_fld = partial(field, hash=False, compare=False)
hashed_fld = partial(field, hash=True, compare=True)


@dataclass(eq=True, unsafe_hash=True, frozen=False)
class AudioContentPackage(AsJsonMixin):
    """Audio content package."""

    download_name: str = nohash_fld()
    package_id: str = hashed_fld()

    download_size: Size = nohash_fld(default_factory=Size)
    file_check: list[str] = nohash_fld(default_factory=list)
    installed_size: Size = nohash_fld(default_factory=Size)
    mandatory: bool = nohash_fld(default=False)
    name: Optional[str] = nohash_fld(default=None)
    version: Optional[vers.Version] = nohash_fld(default=None)
    download_path: Optional[str] = nohash_fld(default=None)

    def __post_init__(self) -> None:
        """Normalize fields after init to expected data types and set empty attributes when we have data.
            - convert 'download_name' into a basename value in its own attribute 'name'
            - clean up extra characters in the 'package_id' value
            - normalize the 'download_name' by removing paths (../<dir>/)
            - normalize 'file_check' into a consistent list[str] instead of inconsistent str/list[str] the
              source metadata flops between
            - convert size values to instances of 'Size' for easy compute + str representation"""
        self.name = Path(self.download_name).name
        self.package_id = self.package_id.strip()
        self.download_path = normalize_package_download_path(self.download_name)
        self.download_size = Size(self.download_size)  # type: ignore[arg-type]
        self.file_check = normalize_file_check_value(self.file_check)  # self._set_file_check_value()
        self.installed_size = Size(self.installed_size)  # type: ignore[arg-type]
        self.mandatory = bool(self.mandatory)  # not all packages have 'mandatory'; default to False

        if self.version is not None:
            self.version = vers.parse(str(self.version))

    def __str__(self) -> str:
        """Custom string representation."""
        return f"{self.name}"

    @property
    def has_sentinel_files(self) -> bool:
        """Sentinel files exist."""
        return found_sentinel_files(self.file_check)

    @property
    def is_installed(self) -> bool:
        """Is the package installed. Uses file sentinel checks and package version checks."""
        # not all package metadata seems to have metadata for package version
        if self.version is None:
            return self.has_sentinel_files

        return installed_version_satisfies_required_version(installed=self.installed_version, required=self.version)

    @property
    def installed_version(self) -> vers.Version:
        """Installed package version. '0.0.0' indicates not installed."""
        if not self.has_sentinel_files:
            return vers.parse("0.0.0")

        return installed_pkg_version(self.package_id)

    def unlink_pkg(self, basedir: Path, *, missing_ok: bool):
        """Unlink/delete the package. Uses the base directory specified and the download_path attribute of own instance
        to use as the file to unlink.
        :param basedir: base directory the package is expected to be in
        :param missing_ok: passed to the path.unlink() call"""
        basedir.joinpath(self.download_path).unlink(missing_ok=missing_ok)
