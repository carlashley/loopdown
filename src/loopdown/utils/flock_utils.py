import fcntl
import logging
import os

from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

log = logging.getLogger(__name__)


class AlreadyRunningError(RuntimeError):
    """Raised when another instance holds the lock."""


@contextmanager
def lock_execution(*, app_name: str) -> Iterator[None]:
    """Prevent multiple instances running.
    :param app_name: app name for error message use"""
    fp: Path = Path("/tmp/loopdown.lock")

    try:
        fp.touch(exist_ok=True)
        os.chmod(fp, 0o666)
    except PermissionError:
        pass

    f = fp.open("a+")  # keep open for lifetime of lock

    try:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log.error(f"Another instance of {app_name} is already running.")
            raise AlreadyRunningError from None

        yield

    finally:
        try:
            fcntl.flock(f, fcntl.LOCK_UN)
        finally:
            f.close()

        try:
            fp.unlink()
        except FileNotFoundError:
            pass
        except PermissionError:
            pass
