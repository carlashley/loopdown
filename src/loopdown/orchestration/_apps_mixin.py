"""Mixin for discovering applications."""
# type: ignore [attr-defined]
# mypy: disable-error-code="attr-defined"
import json
import logging
import subprocess

from typing import Iterator, Optional

from .._config import ApplicationConsts as Consts
from ..models.application import Application

log = logging.getLogger(__name__)


def system_profiler(sp_type: str) -> Optional[dict]:
    """Subprocess the '/usr/sbin/system_profiler' binary.
    :param sp_type: system profiler data type; for example 'SPApplicationsDataType'"""
    cmd = ["/usr/sbin/system_profiler", "-json", "-detaillevel", "full", sp_type]

    try:
        log.debug("Subprocessing '%s'", " ".join(cmd))
        p = subprocess.run(cmd, capture_output=True, check=True)
    except subprocess.CalledProcessError as e:
        stdout = str(e.stdout.decode() if isinstance(e.stdout, bytes) else e.stdout or "").strip()
        stderr = str(e.stderr.decode() if isinstance(e.stderr, bytes) else e.stderr or "").strip()
        msg = "Subprocess '%s' exited with returncode %s; stdout=%s, stderr=%s"
        log.debug(msg, " ".join(cmd), e.returncode, stdout, stderr)
        return None

    try:
        return json.loads(p.stdout).get(sp_type)
    except json.JSONDecodeError as e:
        log.debug("JSON decode error while parsing system_profiler result: %s", str(e))

        return None


class ApplicationDiscoveryMixin:
    """Holds methods for installed audio application discovery."""

    def find_installed_apps(self) -> Iterator[Application]:
        """Find installed applications that content can be processed for."""
        sp_apps_data = system_profiler("SPApplicationsDataType")

        if sp_apps_data is None:
            return

        for app in sp_apps_data:
            if app.get("_name", "").casefold() not in Consts.REAL_NAMES:
                continue

            obj = Application.from_dict(app)

            if obj is None:
                continue

            log.debug("Found installed application %s", obj)
            yield obj
