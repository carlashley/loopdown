"""Model classes"""
from dataclasses import dataclass, field
from pathlib import Path

from .utils import bytes2hr


@dataclass
class Size:
    filesize: int | float = field(default=None)

    def __repr__(self):
        return bytes2hr(self.filesize)

    def __str__(self):
        return bytes2hr(self.filesize)


@dataclass(eq=True, frozen=True)
class LoopDownloadPackage:
    is_mandatory: bool = field(default=None, hash=False, compare=False)
    download_name: str = field(default=None, hash=False, compare=False)
    download_dest: Path = field(default=None, hash=False, compare=False)
    download_size: int | float = field(default=None, hash=False, compare=False)
    download_url: str = field(default=None, hash=False, compare=False)
    package_id: str = field(default=None, hash=True, compare=True)
    status_code: int | str = field(default=None, hash=False, compare=False)
    status_ok: bool = field(default=None, hash=False, compare=False)
    is_compressed: bool = field(default=None, hash=False, compare=False)
    is_installed: bool = field(default=None, hash=True, compare=True)
    file_check: list[str] | str = field(default=None, hash=False, compare=False)
    install_size: int | float = field(default=None, hash=False, compare=False)
    install_target: str = field(default="/", hash=False, compare=False)
    package_vers: str = field(default="0.0.0", hash=False, compare=False)

    # String representation for simple output
    def __repr__(self):
        if not self.status_ok:
            s_msg = f"HTTP error {self.status_code}" if not self.status_code == -999 else "curl error"
            return f"{self.download_url} ({s_msg})"
        else:
            return f"{self.download_url} ({self.download_size} download)"
