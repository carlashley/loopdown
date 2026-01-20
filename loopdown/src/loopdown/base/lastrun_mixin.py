import logging

from collections.abc import Mapping
from dataclasses import asdict, is_dataclass
from functools import cached_property
from typing import Any, Optional

from ..consts.version_enums import VersionConsts
from ..utils.date_utils import datetimestamp, get_local_tz_offset_and_sanitized_name
from ..utils.system_utils import sw_vers

audit_log = logging.getLogger("loopdown.audit")


class AuditLogMixin:
    """Audit logging mixin for LoopdownContext class."""

    @cached_property
    def timezone_and_offset(self) -> dict[str, int | str]:
        """Return timezone and offset meta dict."""
        offset, timezone = get_local_tz_offset_and_sanitized_name()

        return {"tz": timezone, "tz_offset": offset}

    def _parse_audit_data(self, data: Optional[Any] = None) -> dict[str, Any]:
        """Parse audit data payload in to a dictionary."""
        payload: Any = data or {}

        if is_dataclass(payload):
            try:
                payload = payload.as_dict()
            except AttributeError:
                payload = asdict(payload)
        elif isinstance(payload, Mapping):
            payload = dict(payload)

        return payload

    def audit(self, event, *, data: Optional[Any] = None) -> None:
        """Write a structured event to the JSON log file. Log level is 'INFO'.
        :param event: event message
        :param data: optional data object to include in event entry; typically a dataclass or Mapping object"""
        payload = self._parse_audit_data(data)
        extra_dict = {"event": event, "run_id": self.RUN_UID, "data": payload}
        audit_log.info(event, extra=extra_dict)

    def audit_debug(self, event, *, data: Optional[Any] = None) -> None:
        """Write a structured event to the JSON log file. Log level is 'DEBUG'.
        :param event: event message
        :param data: optional data object to include in event entry; typically a dataclass or Mapping object"""
        payload = self._parse_audit_data(data)
        extra_dict = {"event": event, "run_id": self.RUN_UID, "data": payload}
        audit_log.debug(event, extra=extra_dict)

    def audit_start(self) -> None:
        """Helper method for audit start event."""
        payload = {
            "ts": datetimestamp(),
            **self.timezone_and_offset,
            "args": vars(self.args),
            "loopdown_version": VersionConsts.VERSION.value,
            "os_platform": VersionConsts.PLATFORM.value,
            "os_version": sw_vers(),
            "python_version": VersionConsts.PYTHON_VERSION.value,
            "content_server": self.server,
        }
        self.audit("run.start", data=payload)

    def audit_stop(self) -> None:
        """Helper method for audit stop event."""
        self.audit("run.stop")
