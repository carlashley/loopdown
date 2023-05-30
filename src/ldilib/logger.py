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


def construct_logger(level: str = "INFO", silent: bool = False) -> logging.Logger:
    """Construct logging.
    :param name: log name (use '__name__' when calling this function).
    :param level: log level value, default is 'INFO'."""
    name = __name__
    log_path = Path("/Users/Shared/loopdown/loopdown.log")

    # Create parent log directory path if it doesn't exist
    if not log_path.parent.exists():
        log_path.parent.mkdir(parents=True, exist_ok=True)

    # Construct the logger instance
    log = logging.getLogger(name)
    log.setLevel(level.upper())
    formatter = logging.Formatter(fmt=LOG_FMT, datefmt=LOG_DATE_FMT)
    fh = RotatingFileHandler(log_path, backupCount=14)  # keep the last 14 logs
    fh.setFormatter(formatter)
    log.addHandler(fh)

    # errors always print to sys.stderr even with silent mode
    add_stream(stream=sys.stderr, filters=STDERR_FILTERS, log=log)

    # Add the stdout log stream if not silent
    if not silent:
        add_stream(stream=sys.stdout, filters=STDOUT_FILTERS, log=log)

    if log_path.exists() and log_path.stat().st_size > 0:
        fh.doRollover()

    return log
