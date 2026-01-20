import argparse

from typing import Protocol, runtime_checkable

from collections.abc import Mapping
from datetime import datetime
from pathlib import Path
from typing import Any, Optional

from packaging import version as vers


@runtime_checkable
class AsDict(Protocol):
    """Protocol for checking dataclasses have an 'as_dict' method."""
    def as_dict(self) -> dict[str, Any]:
        ...


@runtime_checkable
class Application(Protocol):
    """Protocol for 'Application' class for type hinting."""

    name: str
    version: str
    path: Path
    last_modified: datetime

    @property
    def packages(self) -> Optional[dict]:
        """Packages metadata from the resource file."""
        ...

    def _find_resource_file(self) -> Optional[Path]:
        """Find the relevant property list resource file containing package metadata."""
        ...

    def _read_metadata_source_file(self, *, mode: str = "rb") -> Optional[dict]:
        """Read the metadata source file.
        :param mode: read mode; default is 'rb'"""
        ...


@runtime_checkable
class LoopdownContext(Protocol):
    """Protocol for 'Context' class for type hinting."""

    args: argparse.Namespace
    server: Optional[str]

    @property
    def installed_apps(self) -> tuple:
        """Applications installed on the system for which content can be downloaded/installed."""
        ...

    @property
    def destination(self) -> str:
        """Download destination. Path instance normalized to string."""
        ...

    @property
    def packages(self) -> Optional[list]:
        """Packages that will need to be processed."""
        ...

    def resolve_server(self) -> str:
        """Server that will be used. Returns value in order of:
        - mirror server argument
        - caching server argument
        - defaults to Apple content server"""
        ...

    def _generate_app_dataclass(self, app: Mapping):
        """Generate a dataclass instance from an app mapping."""
        ...

    def _log_context_info(self) -> None:
        """Logs important info for debugging."""
        ...


@runtime_checkable
class Size(Protocol):
    """Protocol 'Size' class for type hinting."""

    raw: int

    @property
    def human(self) -> str:
        ...


@runtime_checkable
class AudioContentPackage(Protocol):
    """Protocol 'AudioContentPackage' class for type hinting."""

    download_name: str
    package_id: str

    download_size: Size
    file_check: list[str]
    installed_size: Size
    mandatory: bool
    name: Optional[str]
    version: vers.Version

    @property
    def download_path(self) -> str:
        """Normalized download path."""
        ...

    @property
    def is_installed(self) -> bool:
        """Is the package installed. Uses file sentinel checks and package version checks."""
        ...

    @property
    def installed_version(self) -> vers.Version:
        """Installed package version. '0.0.0' indicates not installed."""
        ...
