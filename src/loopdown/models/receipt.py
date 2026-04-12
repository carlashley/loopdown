import argparse

from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Self

from packaging import version as vers


MODERN_RECEIPT_ATTRS_MAP = {
    "Build": "build",
    "Bundle Identifier": "bundle_id",
    "Bundle Name": "bundle_name",
    "FileChecks": "file_checks",
    "PackageVersion": "package_version",
    "Revision": "revision",
}


def normalize_file_checks(v: Any, *, args: argparse.Namespace) -> list[Path]:
    """Normalize the modern file checks values.
    :param v: Any"""
    base = args.library_path

    if isinstance(v, str):
        return [base.joinpath(Path(v))]
    elif isinstance(v, list) and all(isinstance(fp, str) for fp in v):
        return [base.joinpath(Path(fp)) for fp in v]

    return v


@dataclass(eq=True, unsafe_hash=True, frozen=False)
class ModernContentReceipt:
    build: int
    bundle_id: str
    bundle_name: str
    file_checks: list[Path] = field(hash=False)
    package_version: vers.Version
    revision: int

    @classmethod
    def from_dict(cls, data: Mapping, *, args: argparse.Namespace) -> Self:
        """Emits an instance of 'ModernAudioContentPackage' from mapping data.
        :param data: raw mapping of package metadata keys to values"""
        kwargs = {}

        for k, v in data.items():
            if k in MODERN_RECEIPT_ATTRS_MAP:
                fld_name = MODERN_RECEIPT_ATTRS_MAP.get(k, k)

                if fld_name == "file_checks":
                    v = normalize_file_checks(v, args=args)

                if fld_name == "package_version":
                    v = vers.parse(str(v))

                kwargs[fld_name] = v

        return cls(**kwargs)
