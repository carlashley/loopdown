"""Mixin for package installation."""
# type: ignore [attr-defined]
# mypy: disable-error-code="attr-defined"
import logging
import subprocess

from pathlib import Path
from typing import Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from ..models.package import AudioContentPackage


log = logging.getLogger(__name__)


def installer(fp: Path, *, target: Optional[str] = None) -> bool:
    """Subprocess '/usr/sbin/installer'.
    :param fp: Path object
    :param target: installation target; default is '/'"""
    cmd = ["/usr/sbin/installer", "-pkg", str(fp), "-target", target or "/"]

    try:
        log.debug("Subprocessing '%s'", " ".join(cmd))
        p = subprocess.run(cmd, capture_output=True, encoding="utf-8", check=True)
    except subprocess.CalledProcessError as e:
        stdout = str(e.stdout or "").strip()
        stderr = str(e.stderr or "").strip()
        msg = "Subprocess '%s' exited with returncode %s; stdout=%s, stderr=%s"
        log.debug(msg, " ".join(cmd), e.returncode, stdout, stderr)
        return False

    lines = (p.stdout or "").splitlines()
    last = lines[-1] if lines else ""
    output = last.split(": ")[-1].strip() if last else ""

    return " success" in output


class InstallationMixin:
    """Holds methods for installing content."""

    def install_pkg(self, pkg: "AudioContentPackage", *, target: Optional[str] = None) -> bool:
        """Install the package. The package file path is calculated internally in this method.
        :param pkg: AudioContentPackage object
        :param target: installation target; default is '/'"""
        fp = self.ctx.args.destination.joinpath(pkg.download_path)
        return installer(fp, target=target)
