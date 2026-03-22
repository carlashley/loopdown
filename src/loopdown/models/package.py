"""Package model."""
# pylint: disable=too-many-instance-attributes
import posixpath

from collections.abc import Mapping
from dataclasses import dataclass, field
from functools import partial
from pathlib import Path
from typing import Optional

from packaging import version as vers

from .size import Size
from ..utils.package_utils import get_pkg_info

DATACLASS_ATTRS_MAP: dict[str, str] = {
    "DownloadName": "download_name",
    "PackageID": "package_id",
    "DownloadSize": "download_size",
    "FileCheck": "file_check",
    "InstalledSize": "installed_size",
    "IsMandatory": "mandatory",
    "PackageVersion": "version",
}

nohash_fld = partial(field, hash=False, compare=False)
hashed_fld = partial(field, hash=True, compare=True)


def found_sentinel_files(v: list[str]) -> bool:
    """Any of the sentinel files were or were not found at the 'file_check' locations.
    :param v: sentinel file values"""
    return any(Path(f).expanduser().exists() for f in v)


def get_installed_pkg_version(pkg_id: str) -> vers.Version:
    """Get the installed version of a package from the package id.
    :param pkg_id: package id"""
    pkginfo = get_pkg_info(pkg_id)

    if pkginfo is None:
        return vers.parse("0.0.0")

    return vers.parse(pkginfo.get("pkg-version", "0.0.0"))


def installed_vers_satisfies_reqd_vers(inst: vers.Version, reqd: vers.Version) -> bool:
    """Use prefix-floor semantics to ensure the installed version satisfies the required version.
    For example, installed=2.1.0.0.1235, required=2.1; installed version satisfies required version.
    :param inst: vers.Version object representing installed version
    :param reqd: vers.Version object representing required version"""
    reqd_rel = reqd.release
    inst_rel = inst.release

    if not reqd_rel:
        return True  # required version is 'odd'; treat as 'no minimum'

    # when installed has fewer components than required, pad with zeroes
    if len(inst_rel) < len(reqd_rel):
        inst_pfx = inst_rel + (0,) * (len(reqd_rel) - len(inst_rel))
    else:
        inst_pfx = inst_rel[: len(reqd_rel)]

    return inst_pfx >= reqd_rel


def normalize_file_check(v: str | list[str]) -> list[str]:
    """Normalize the 'file_check' attribute to always be a list[str]. The metadata mixes these values in each package
    meta object as either a string or an array of strings.
    :param v: value"""
    if isinstance(v, str):
        return [v]

    return v


def normalize_url_path(p: str) -> str:
    """Normalize a path of a URL; collapse multiple slashes in paths and resolve '../' type paths to natural path.
    This presumes that the standard top path component is 'lp10_ms3_content_2016' so it is always pre-pended to the
    path (current behaviour in the metadata files does not include that path component, but always includes the
    '../lp10_ms3_content_2013' component in the download name, suggesting that Apple's software always pre-pends the
    2016 component).
    :param p: path value"""
    path = f"lp10_ms3_content_2016/{p}"
    normalized = posixpath.normpath(path)

    # ensure trailing slash is preserved, not likely to need this though
    if p.endswith("/") and not normalized.endswith("/"):
        normalized += "/"

    return normalized


@dataclass(eq=True, unsafe_hash=True, frozen=False)
class AudioContentPackage:
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

    @classmethod
    def from_dict(cls, data: Mapping) -> "AudioContentPackage":
        """Emits an instance of 'AudioContentPackage' from mapping data.
        :param data: raw mapping of package metadata keys to values"""
        values = {mapped_attr: data.get(attr) for attr, mapped_attr in DATACLASS_ATTRS_MAP.items()}

        return cls(**values)

    def __post_init__(self) -> None:
        """Normalizes attributes after initializing."""
        self.name = Path(self.download_name).name
        self.package_id = self.package_id.strip()
        self.download_path = normalize_url_path(self.download_name)
        self.download_size = Size(self.download_size)  # type: ignore[arg-type]
        self.file_check = normalize_file_check(self.file_check)
        self.installed_size = Size(self.installed_size)  # type: ignore[arg-type]
        self.mandatory = bool(self.mandatory)  # not all packages have 'mandatory'; default to False

        if self.version is not None:
            self.version = vers.parse(str(self.version))

    def __str__(self) -> str:
        """Custom string representation."""
        return self.name

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

        return installed_vers_satisfies_reqd_vers(self.installed_version, self.version)

    @property
    def installed_version(self) -> vers.Version:
        """Installed package version. '0.0.0' indicates not installed."""
        if not self.has_sentinel_files:
            return vers.parse("0.0.0")

        return get_installed_pkg_version(self.package_id)

    def unlink(self, basedir: Path, *, missing_ok: bool) -> None:
        """Unlink (delete) the package.
        :param basedir: base directory where the package should be located (package download path added to this value)
        :param missing_ok: don't raise an error if the file is missing when True"""
        if self.download_path is not None:
            basedir.joinpath(self.download_path).unlink(missing_ok=missing_ok)
