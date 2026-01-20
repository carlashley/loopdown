from dataclasses import dataclass, field
from functools import total_ordering

from .json_mixin import AsJsonMixin
from .protocol_types import AudioContentPackage
from ..utils.normalizers import bytes2hr


@total_ordering  # implements comparisons like >=, <=
@dataclass(slots=True)
class Size(AsJsonMixin):
    """Package size class. Has human readable property and a raw value property.
    Implements __add__ and __iadd__ (accumulation) methods.
    This presumes size data is immutable."""

    raw: int = field(default=0)

    @property
    def human(self) -> str:
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

    def __lt__(self, other: object):  # type: ignore[arg=type]
        if not isinstance(other, Size):
            return NotImplemented

        return self.raw < other.raw


@dataclass(slots=True)
class BucketStats:
    """Accumulates counts and sizes for a package bucket."""
    count: int = 0
    down: Size = field(default_factory=Size)
    inst: Size = field(default_factory=Size)

    def add(self, pkg: AudioContentPackage) -> None:
        self.count += 1
        self.down += pkg.download_size
        self.inst += pkg.installed_size

    def __add__(self, other: "BucketStats") -> "BucketStats":
        out = BucketStats()
        out.count = self.count + other.count
        out.down = self.down + other.down
        out.inst = self.inst + other.inst

        return out
