"""File locking and signal handler utils."""

import fcntl
import logging
import os
import signal

from collections.abc import Callable
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

log = logging.getLogger(__name__)

Handler = Callable[[int, object], None]


def install_termination_handlers(*, raise_kb_interrupt: bool = True) -> None:
    """install signal handlers so SIGTERM triggers clean shutdown.
    :param raise_kb_interrupt: SIGTERM raises 'KeyboardInterrupt' if 'True' so it follows
                               the same cleanup path as CTRL+C; if 'False', raises SystemExit(143)"""
    def _handle_sigterm(_signum: int, _frame: object) -> None:
        # _signum and _frame intentionally unused.
        if raise_kb_interrupt:
            raise KeyboardInterrupt

        raise SystemExit(143)

    signal.signal(signal.SIGTERM, _handle_sigterm)


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

    f = fp.open("ab+")  # keep open for lifetime of lock, open in binary mode because encoding doesn't matter here

    try:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log.error("Another instance of %s is already running.", app_name)
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
