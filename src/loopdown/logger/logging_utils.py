import logging
import logging.config
import logging.handlers

from logging import StreamHandler
from pathlib import Path
from typing import Any

from .logger_filter_utils import AnyOfLevelsFilter, ExactLevelFilter
from .logging_formatters import JsonFormatter

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
    except OSError:
        return False

    handler.doRollover()
    return True


def human_logging_config(level: str, *, path: Path) -> dict:
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
                "filters": ["only_info"],
                "stream": "ext://sys.stdout",
            },
            "stderr": {
                "class": "logging.StreamHandler",
                "level": "NOTSET",
                "formatter": "console",
                "filters": ["warn_or_error"],
                "stream": "ext://sys.stderr",
            },
        },
        "root": {
            "level": LOG_LEVELS[level],
            "handlers": ["file", "stdout", "stderr"],
        },
        "loggers": {
            "loopdown.fileonly": {"level": "INFO", "propagate": False, "handlers": ["file"]},
            "requests": {"level": "WARNING", "propagate": False, "handlers": []},
            "tzlocal": {"level": "WARNING", "propagate": False, "handlers": []},
            "urllib3": {"level": "WARNING", "propagate": False, "handlers": []},
        },
    }


def mixed_logging_config(level: str, *, path: Path) -> dict[str, Any]:
    if level not in LOG_LEVELS:
        raise ValueError(f"log {level=} invalid; must be from {tuple(LOG_LEVELS.keys())}")

    return {
        "version": 1,
        "disable_existing_loggers": False,
        "filters": {
            "only_info": {"()": ExactLevelFilter, "levelno": logging.INFO},
            "warn_or_error": {"()": AnyOfLevelsFilter, "levelnos": [logging.WARNING, logging.ERROR]},
        },
        "formatters": {
            "console": {"format": "%(message)s"},
            "json": {"()": JsonFormatter},
        },
        "handlers": {
            "file_json": {
                "class": "logging.handlers.RotatingFileHandler",
                "level": "NOTSET",
                "formatter": "json",
                "filename": str(path),
                "maxBytes": MAX_BYTES,
                "backupCount": BACKUP_COUNT,
                "encoding": "utf-8",
                "delay": True,
            },
            "stdout": {
                "class": "logging.StreamHandler",
                "level": "NOTSET",
                "formatter": "console",
                "filters": ["only_info"],
                "stream": "ext://sys.stdout",
            },
            "stderr": {
                "class": "logging.StreamHandler",
                "level": "NOTSET",
                "formatter": "console",
                "filters": ["warn_or_error"],
                "stream": "ext://sys.stderr",
            },
        },
        "root": {
            "level": LOG_LEVELS[level],
            "handlers": ["file_json", "stdout", "stderr"],
        },
        "loggers": {
            # file-only structured/audit logger
            "loopdown.audit": {"level": LOG_LEVELS[level], "propagate": False, "handlers": ["file_json"]},
            "requests": {"level": "WARNING", "propagate": False, "handlers": []},
            "tzlocal": {"level": "WARNING", "propagate": False, "handlers": []},
            "urllib3": {"level": "WARNING", "propagate": False, "handlers": []},
        },
    }


def mute_console_logging() -> None:
    """Remove all StreamHandlers (stdout/stderr) from the root logger when necessary."""
    root = logging.getLogger()

    for handler in root.handlers[:]:
        # logging.FileHandler/RotatingFileHandler subclass StreamHandler, so only remove
        # on handlers that _are_ StreamHandler
        if type(handler) is StreamHandler:
            root.removeHandler(handler)


def configure_logging(level: str, *, path: str | Path, quiet: bool) -> dict:
    """Configure logging.
    :param level: log level; for example 'info'
    :param path: log file path; for example '/Users/Shared/loopdown/loopdown.log'
    :param quiet: boolean value indicating all stdout/stderr streaming should stop in a 'quiet' mode"""
    path = Path(path)
    # parent directory must exist; create if it doesn't
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch(exist_ok=True)  # ensure file exists even when delay=True
    except OSError:
        pass  # dictconfig will fail with a clearer error if we can't create directories

    # log_cfg = human_logging_config(level, path=path)
    log_cfg = mixed_logging_config(level, path=path)
    logging.config.dictConfig(log_cfg)

    root = logging.getLogger()

    for h in root.handlers:
        if isinstance(h, logging.handlers.RotatingFileHandler):
            rollover_log_files(h)
            break

    if quiet:
        mute_console_logging()

    return log_cfg
