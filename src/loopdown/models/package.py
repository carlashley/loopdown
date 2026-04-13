"""Package model."""

# pylint: disable=too-many-instance-attributes
import argparse
import logging
import plistlib
import posixpath

from collections.abc import Mapping
from dataclasses import dataclass, field, fields
from functools import partial
from pathlib import Path
from typing import get_type_hints, Any, Optional, Self

from packaging import version as vers

from .receipt import ModernContentReceipt
from .size import Size
from .._config import ServerBases
from ..utils.package_utils import get_pkg_info

log = logging.getLogger(__name__)

LEGACY_DATACLASS_ATTRS_MAP: dict[str, str] = {
    "DownloadName": "download_name",
    "PackageID": "package_id",
    "DownloadSize": "download_size",
    "FileCheck": "file_check",
    "InstalledSize": "installed_size",
    "IsMandatory": "is_core",
    "PackageVersion": "version",
}

nohash_fld = partial(field, hash=False, compare=False)
hashed_fld = partial(field, hash=True, compare=True)


def found_sentinel_files(v: list[str], *, check_all: bool) -> bool:
    """Any of the sentinel files were or were not found at the 'file_check' locations.
    :param v: sentinel file values"""
    if check_all:
        return all(Path(f).expanduser().exists() for f in v)

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


def normalize_url_path(p: str, *, is_legacy: bool) -> str:
    """Normalize a path of a URL; collapse multiple slashes in paths and resolve '../' type paths to natural path.
    This presumes that the standard top path component is 'lp10_ms3_content_2016' so it is always pre-pended to the
    path (current behaviour in the metadata files does not include that path component, but always includes the
    '../lp10_ms3_content_2013' component in the download name, suggesting that Apple's software always pre-pends the
    2016 component).
    :param p: path value"""
    if is_legacy:
        path = f"lp10_ms3_content_2016/{p}"
    else:
        path = f"{ServerBases.MODERN}/{p}"

    normalized = posixpath.normpath(path)

    # ensure trailing slash is preserved, not likely to need this though
    if p.endswith("/") and not normalized.endswith("/"):
        normalized += "/"

    return normalized


@dataclass(eq=True, unsafe_hash=True, frozen=False)
class _AudioContentPackage:
    """Parent class for LegacyAudioContentPackage and ModernAudioContentPackage."""

    download_name: str = nohash_fld()
    package_id: str = hashed_fld()

    download_size: Size = nohash_fld(default_factory=Size)
    file_check: list[str] = nohash_fld(default_factory=list)
    installed_size: Size = nohash_fld(default_factory=Size)
    is_legacy: bool = nohash_fld(default=True)
    is_core: bool = nohash_fld(default=False)
    is_essential: bool = nohash_fld(default=False)
    is_optional: bool = nohash_fld(default=False)
    name: Optional[str] = nohash_fld(default=None)
    version: Optional[vers.Version] = nohash_fld(default=None)
    download_path: Optional[str] = nohash_fld(default=None)

    def __str__(self) -> str:
        """Custom string representation."""
        return self.name

    @property
    def has_sentinel_files(self) -> bool:
        """Sentinel files exist."""
        return found_sentinel_files(self.file_check, check_all=False)

    def unlink(self, basedir: Path, *, missing_ok: bool) -> None:
        """Unlink (delete) the package.
        :param basedir: base directory where the package should be located (package download path added to this value)
        :param missing_ok: don't raise an error if the file is missing when True"""
        if self.download_path is not None:
            basedir.joinpath(self.download_path).unlink(missing_ok=missing_ok)


@dataclass(eq=True, unsafe_hash=True, frozen=False)
class AudioContentPackage(_AudioContentPackage):
    """Audio content package."""

    @classmethod
    def from_dict(cls, data: Mapping) -> Optional[Self]:
        """Emits an instance of 'AudioContentPackage' from mapping data.
        :param data: raw mapping of package metadata keys to values"""
        kwargs = {mapped_attr: data.get(attr) for attr, mapped_attr in LEGACY_DATACLASS_ATTRS_MAP.items()}

        try:
            return cls(**kwargs)
        except Exception as e:
            log.error("Failed to create %s from data: %s", cls.__name__, str(e))
            return None

    def __post_init__(self) -> None:
        """Normalizes attributes after initializing."""
        self.name = Path(self.download_name).name
        self.package_id = self.package_id.strip()
        self.download_path = normalize_url_path(self.download_name, is_legacy=self.is_legacy)
        self.download_size = Size(self.download_size)  # type: ignore[arg-type]
        self.file_check = normalize_file_check(self.file_check)
        self.installed_size = Size(self.installed_size)  # type: ignore[arg-type]
        self.is_core = bool(self.is_core)  # not all packages have 'is_core'; default to False

        if self.version is not None:
            self.version = vers.parse(str(self.version))

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

    @property
    def metadata(self) -> None:
        """Metadata."""
        # deliberately using a property method here to avoid issues with metadata being specific to modern content
        return None


MODERN_DATACLASS_ATTRS_MAP: dict[str, str] = {
    "download_name": "download_name",
    "is_core": "is_core",
    "is_essential": "is_essential",
    "is_optional": "is_optional",
    "package_id": "package_id",
    "server_path": "download_path",
    "server_version": "version",
}


@dataclass(eq=True, unsafe_hash=True, frozen=False)
class MinimumAppVersion:
    logicpro: float | None = None
    mainstage: float | None = None


@dataclass(eq=True, unsafe_hash=True, frozen=False)
class ModernContentPackageMetadata:
    """Metadata specific to modern audio content packages."""

    category: str
    id: int
    in_app_package: bool
    in_store_front: bool
    installed_date: Optional[int]
    installed_local_version: int
    logic_item_count: int
    minimum_soc_version: bool
    receipt: ModernContentReceipt = field(hash=False)
    server_path: str
    server_version: int
    total_item_count: int
    minimum_app_version: Optional[MinimumAppVersion] = field(hash=False, default=None)

    @classmethod
    def from_dict(cls, data: Mapping) -> Self:
        """Emits an instance of 'ModernContentPackageMetadata' from mapping data.
        :param data: raw mapping of package metadata keys to values"""
        min_app_vers = data.pop("minimum_app_version", None)
        kwargs = {**data}

        if min_app_vers is not None:
            kwargs["minimum_app_version"] = MinimumAppVersion(**min_app_vers)

        return cls(**kwargs)


@dataclass(eq=True, unsafe_hash=True, frozen=False)
class ModernAudioContentPackage(_AudioContentPackage):
    """Modernised audio content package."""

    metadata: Optional[dict[str, Any]] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: Mapping, *, args: argparse.Namespace) -> Optional[Self]:
        """Emits an instance of 'ModernAudioContentPackage' from mapping data.
        :param data: raw mapping of package metadata keys to values"""
        hints = get_type_hints(cls)
        metadata = {}
        kwargs = {"metadata": {}}
        fld_names = tuple(fld.name for fld in fields(cls) if fld.name != "metadata")

        if args is not None:
            kwargs["file_check"] = ["some files to check"]

        for k, v in data.items():
            fld_name = MODERN_DATACLASS_ATTRS_MAP.get(k, k)

            if k not in fld_names:
                metadata[k] = data[k]
                continue

            if hints[k] is bool:
                value = bool(data[k])
            elif k == "download_name":
                value = Path(data[k]).name
            else:
                value = data[k]

            kwargs[fld_name] = value

        receipt = cls.get_receipt(kwargs.get("download_name"), args=args)
        kwargs["file_check"] = receipt.file_checks if receipt is not None else []
        metadata["receipt"] = receipt
        kwargs["metadata"] = ModernContentPackageMetadata.from_dict(metadata)

        return cls(**kwargs)

    @classmethod
    def get_receipt(cls, fn: str | None, *, args: argparse.Namespace) -> ModernContentReceipt | None:
        if fn is None:
            return None

        fp = args.library_path.joinpath(f"Application Support/Package Definitions/{Path(fn).stem}.plist")

        try:
            with fp.open("rb") as f:
                data = plistlib.load(f)
                return ModernContentReceipt.from_dict(data, args=args) if data else None
        except Exception:
            return None

    def __post_init__(self) -> None:
        """Normalizes attributes after initializing."""
        self.package_id = self.package_id.strip()
        self.download_size = Size(self.download_size)  # type: ignore[arg-type]
        self.installed_size = Size(self.installed_size)  # type: ignore[arg-type]
        self.download_path = normalize_url_path(self.metadata.server_path, is_legacy=self.is_legacy)

        if self.version is not None:
            self.version = vers.parse(str(self.version))

    @property
    def has_sentinel_files(self) -> bool:
        """Sentinel files exist."""
        if not self.file_check:
            return False

        return found_sentinel_files(self.file_check, check_all=True)

    @property
    def is_installed(self) -> bool:
        """Is the package installed. Uses file sentinel checks. This check is slightly different to how legacy
        content packages are checked."""
        return self.has_sentinel_files

    @property
    def installed_version(self) -> vers.Version:
        """Installed package version. '0.0.0' indicates not installed."""
        if not self.has_sentinel_files:
            return vers.parse("0.0.0")

        return vers.parse("0.0.0")
