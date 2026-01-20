import json
import logging

from logging import LogRecord
from typing import Any

from ..utils.date_utils import datetimestamp


def _get_reserved_log_record_attrs() -> set[str]:
    """Determine reserved attributes of a log record so we don't clash when logging."""
    r = LogRecord(name="__probe__", level=logging.INFO, pathname="", lineno=0, msg="", args=(), exc_info=None)

    return r.__dict__.keys()


class JsonFormatter(logging.Formatter):
    """Strict JSON log formatter with structured event support."""

    _reserved_attrs = _get_reserved_log_record_attrs()
    _common_structure_fields = ("event", "run_id", "data")

    def format(self, record: logging.LogRecord) -> str:
        """Overrides logging.Formatter.format to implement JSON log format."""
        payload: dict[str, Any] = {
            "ts": datetimestamp(record.created),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        # facilitate common structured fields (if present)
        for fld in self._common_structure_fields:
            if hasattr(record, fld):
                payload[fld] = getattr(record, fld)

        # include other non-reserved extras
        for k, v in record.__dict__.items():
            if k in self._reserved_attrs or k in payload:
                continue

            payload[k] = v

        # include exception/stack info if present
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)  # format for logging

        if record.stack_info:
            payload["stack"] = record.stack_info

        # note, 'default=str' is there to stop crashes when logging if there is something that JSON can't serialize;
        # still need to ensure clean data is passed through
        return json.dumps(payload, ensure_ascii=False, default=str)
