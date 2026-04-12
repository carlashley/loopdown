"""File/install size model."""

from dataclasses import dataclass, field
from functools import total_ordering
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .package import _AudioContentPackage


def bytes2hr(v: str | int | float, *, bs: float = 1000.0) -> str:
    """Convert bytes size value to human readable value. Returns SI Unit style suffixes (KB, MB, GB, etc).
    :param v: value
    :param bs: block size; default is 1000 (closest match to Apple behaviour for human friendly file sizes)"""
    v, idx = float(v), 0  # convert v to int, and set default index starting point
    suffixes = ("B", "KB", "MB", "GB", "TB", "PB")

    while v > bs and idx < len(suffixes) - 1:
        idx += 1
        v /= bs

    return f"{v:.2f}{suffixes[idx]}"


@total_ordering  # implements comparisons like >=, <=
@dataclass(slots=True)
class Size:
    """Package size class. Has human readable property and a raw value property."""

    raw: int = field(default=0)

    @property
    def human(self) -> str:
        """Raw value converted to human friendly string."""
        return bytes2hr(self.raw)

    def __str__(self) -> str:
        return self.human

    def __add__(self, other: object):  # type: ignore[arg-type]
        # add
        if not isinstance(other, Size):
            return NotImplemented

        return Size(
            raw=self.raw + other.raw,
        )

    def __iadd__(self, other: object):  # type: ignore[arg-type]
        # += accumulation
        if not isinstance(other, Size):
            return NotImplemented

        self.raw += other.raw

        return self

    def __eq__(self, other: object):  # type: ignore[arg-type]
        if not isinstance(other, Size):
            return NotImplemented

        return self.raw == other.raw

    def __lt__(self, other: object):  # type: ignore[arg-type]
        if not isinstance(other, Size):
            return NotImplemented

        return self.raw < other.raw


@dataclass(slots=True)
class BucketStats:
    """Accumulates counts and sizes for a package bucket."""
    count: int = 0
    down: Size = field(default_factory=Size)
    inst: Size = field(default_factory=Size)

    def add(self, pkg: "_AudioContentPackage") -> None:
        """Accumulate package sizes and increment count."""
        self.count += 1
        self.down += pkg.download_size
        self.inst += pkg.installed_size

    def __add__(self, other: "BucketStats") -> "BucketStats":
        out = BucketStats()
        out.count = self.count + other.count
        out.down = self.down + other.down
        out.inst = self.inst + other.inst

        return out
