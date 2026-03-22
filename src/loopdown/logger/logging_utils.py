"""Logging configuration and utils."""

import logging
import logging.config
import logging.handlers

from logging import StreamHandler
from pathlib import Path

from .logger_filter_utils import AnyOfLevelsFilter, ExactLevelFilter, FileOnlyFilter

log = logging.getLogger(__name__)


MAX_BYTES = 10 * 1024 * 1024  # 10MiB
BACKUP_COUNT = 7

LOG_LEVELS = {
    "critical": logging.CRITICAL,
    "error": logging.ERROR,
    "warning": logging.WARNING,
    "info": logging.INFO,
    "debug": logging.DEBUG,
    "notset": logging.NOTSET,
}


def rollover_log_files(handler: logging.handlers.RotatingFileHandler) -> bool:
    """Rollover log files. Returns a bool value indicating success/failure of rollover.
    :param handler: the rotating file handler instance"""
    base = Path(handler.baseFilename)

    try:
        if not base.exists() or base.stat().st_size == 0:
            return False
    except OSError as e:
        log.debug("Error rolling over log files: %s", str(e))
        return False

    handler.doRollover()
    return True


def logging_config(level: str, *, path: Path) -> dict:
    """Returns a dictionary for logging configuration.
    :param level: log level; for example 'info'
    :param path: log file path; for example '/Users/Shared/loopdown/loopdown.log'"""
    if level not in LOG_LEVELS:
        raise ValueError(f"log {level=} invalid; must be from {tuple(LOG_LEVELS.keys())}")

    file_fmt = "%(asctime)s - %(levelname)8s - %(name)s: %(message)s"
    date_fmt = "%Y-%m-%d %H:%M:%S"

    return {
        "version": 1,
        "disable_existing_loggers": False,
        "filters": {
            "only_info": {
                "()": ExactLevelFilter,
                "levelno": logging.INFO,
            },
            "warn_or_error": {
                "()": AnyOfLevelsFilter,
                "levelnos": [logging.WARNING, logging.ERROR],
            },
            "not_file_only": {"()": FileOnlyFilter},
        },
        "formatters": {
            "file": {
                "class": "logging.Formatter",
                "format": file_fmt,
                "datefmt": date_fmt,
            },
            "console": {
                "format": "%(message)s",
            },
        },
        "handlers": {
            "file": {
                "class": "logging.handlers.RotatingFileHandler",
                "level": "NOTSET",
                "formatter": "file",
                "filename": str(path),
                "maxBytes": MAX_BYTES,
                "backupCount": BACKUP_COUNT,
                "encoding": "utf-8",
                "delay": True,  # critical: avoids creating empty files until first emit
            },
            "stdout": {
                "class": "logging.StreamHandler",
                "level": "NOTSET",
                "formatter": "console",
                "filters": ["not_file_only", "only_info"],
                "stream": "ext://sys.stdout",
            },
            "stderr": {
                "class": "logging.StreamHandler",
                "level": "NOTSET",
                "formatter": "console",
                "filters": ["not_file_only", "warn_or_error"],
                "stream": "ext://sys.stderr",
            },
        },
        "root": {
            "level": LOG_LEVELS[level],
            "handlers": ["file", "stdout", "stderr"],
        },
        "loggers": {
            "requests": {"level": "WARNING", "propagate": False, "handlers": []},
            "urllib3": {"level": "WARNING", "propagate": False, "handlers": []},
        },
    }


def mute_console_logging() -> None:
    """Remove all StreamHandlers (stdout/stderr) from the root logger when necessary."""
    root = logging.getLogger()

    # pylint: disable=unidiomatic-typecheck
    for handler in root.handlers[:]:
        # logging.FileHandler/RotatingFileHandler subclass StreamHandler, so only remove
        # on handlers that _are_ StreamHandler; yes this could break subclassed handlers like 'RichHandler',
        # but those aren't used, so I don't care.
        if type(handler) is StreamHandler:
            root.removeHandler(handler)
    # pylint: enable=unidiomatic-typecheck


def configure_logging(level: str, *, path: str | Path, quiet: bool) -> None:
    """Configure logging.
    :param level: logging level; for example 'info'
    :param path: log file path
    :param quiet: suppress all console output when True"""
    path = Path(path)
    # parent directory must exist; create if it doesn't
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch(exist_ok=True)  # ensure file exists even when delay=True
    except OSError:
        pass  # dictconfig will fail with a clearer error if we can't create directories

    log_cfg = logging_config(level, path=path)
    logging.config.dictConfig(log_cfg)

    root = logging.getLogger()

    for h in root.handlers:
        if isinstance(h, logging.handlers.RotatingFileHandler):
            rollover_log_files(h)
            break

    if quiet:
        mute_console_logging()
