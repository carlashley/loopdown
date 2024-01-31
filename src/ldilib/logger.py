import logging
import sys

from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import TextIO

LOG_FMT: str = "%(asctime)s - %(name)s.%(funcName)s - %(levelname)s - %(message)s"
LOG_DATE_FMT: str = "%Y-%m-%d %H:%M:%S"
STDOUT_FILTERS: list[int] = [logging.INFO]
STDERR_FILTERS: list[int] = [logging.DEBUG, logging.ERROR, logging.CRITICAL]


def add_stream(stream: TextIO, filters: list[int], log: logging.Logger) -> None:
    """Add a stdout or stderr stream handler
    :param stream: sys.stdout or sys.stderr
    :param filters: logging levels to filter
    :param log: logger to add handlers to"""
    h: logging.StreamHandler = logging.StreamHandler(stream)
    h.addFilter(lambda log: log.levelno in filters)

    if stream == sys.stdout:
        h.setLevel(logging.INFO)
    elif stream == sys.stderr:
        h.setLevel(logging.ERROR)

    log.addHandler(h)


def construct_logger(level: str, dest: Path, silent: bool) -> logging.Logger:
    """Construct logging.
    :param dest: log directory destination; this should be a directory only, not an actual file
    :param level: log level value, default is 'INFO'.
    :param silent: bool, disables (True)/enables (False) logging output to stdout"""
    name = __name__
    fp = dest.joinpath("loopdown.log")

    # Create parent log directory path if it doesn't exist
    if not fp.parent.exists():
        fp.parent.mkdir(parents=True, exist_ok=True)

    # Construct the logger instance
    log = logging.getLogger(name)
    log.setLevel(level.upper())
    formatter = logging.Formatter(fmt=LOG_FMT, datefmt=LOG_DATE_FMT)
    fh = RotatingFileHandler(fp, backupCount=14)  # keep the last 14 logs
    fh.setFormatter(formatter)
    log.addHandler(fh)

    # errors always print to sys.stderr even with silent mode
    add_stream(stream=sys.stderr, filters=STDERR_FILTERS, log=log)

    # Add the stdout log stream if not silent
    if not silent:
        add_stream(stream=sys.stdout, filters=STDOUT_FILTERS, log=log)

    if fp.exists() and fp.stat().st_size > 0:
        fh.doRollover()

    return log
