"""Mixin for system information."""
# type: ignore [attr-defined]
# mypy: disable-error-code="attr-defined"
import logging
import subprocess

from typing import Optional

log = logging.getLogger(__name__)


def sw_vers() -> Optional[str]:
    """Subprocess the '/usr/bin/sw_vers' binary."""
    cmd = ["/usr/bin/sw_vers"]

    try:
        log.debug("Subprocessing '%s'", " ".join(cmd))
        p = subprocess.run(cmd, capture_output=True, encoding="utf-8", check=True)
    except subprocess.CalledProcessError as e:
        stdout = str(e.stdout or "").strip()
        stderr = str(e.stderr or "").strip()
        msg = "Subprocess '%s' exited with returncode %s; stdout=%s, stderr=%s"
        log.debug(msg, " ".join(cmd), e.returncode, stdout, stderr)
        return None

    lines = p.stdout.strip().splitlines()
    vers_str = []

    for ln in lines:
        attr, val = [v.strip() for v in ln.split(":")]

        if attr == "BuildVersion":
            val = f"({val})"

        vers_str.append(val)

    return " ".join(vers_str)


class SystemInfoMixin:
    """Holds methods for system information data like OS version"""

    def get_os_vers(self) -> str:
        """Get the OS version."""
        return sw_vers()
