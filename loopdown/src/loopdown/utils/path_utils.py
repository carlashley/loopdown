import os

from collections.abc import Iterator
from pathlib import Path


def _rglob_plist_str(root: str) -> Iterator[Path]:
    """Yield .plist files under a root path using os.scandir (faster than Path.rglob).
    :param root: path object to glob"""
    try:
        with os.scandir(root) as it:
            for entry in it:
                try:
                    if entry.is_dir(follow_symlinks=False):
                        yield from _rglob_plist_str(entry.path)
                    elif entry.is_file(follow_symlinks=False) and entry.name.endswith(".plist"):
                        yield Path(entry.path)
                except PermissionError:
                    continue
    except FileNotFoundError:
        return
    except NotADirectoryError:
        return


def rglob_plist(root: Path) -> Iterator[Path]:
    """Yield .plist files under a root path using os.scandir (faster than Path.rglob).
    :param root: path object to glob"""
    yield from _rglob_plist_str(os.fspath(root))
