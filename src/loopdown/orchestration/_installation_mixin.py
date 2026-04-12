"""Mixin for package installation."""

# type: ignore [attr-defined]
# mypy: disable-error-code="attr-defined"
import logging
import subprocess

from pathlib import Path
from typing import Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from ..models.package import _AudioContentPackage


log = logging.getLogger(__name__)


def aa(*args, **kwargs) -> Optional[subprocess.CompletedProcess]:
    """Subprocess the '/usr/bin/aa' binary.
    :param *args: argument sequence passed to the binary
    :param **kwargs: keyword arguments passed to the subprocess.run call"""
    cmd = ["/usr/bin/aa", *args]
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("check", True)
    kwargs.setdefault("encoding", "utf-8")

    try:
        log.debug("Subprocessing '%s'", " ".join(cmd))
        return subprocess.run(cmd, **kwargs)
    except subprocess.CalledProcessError as e:
        stderr = (e.stderr or "").strip()
        msg = "Subprocess '%s' exited with returncode %s; stderr=%s"
        log.debug(msg, " ".join(cmd), e.returncode, stderr)
        return None


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

    def install_pkg(self, pkg: "_AudioContentPackage", *, target: Optional[str] = None) -> bool:
        """Install the package. The package file path is calculated internally in this method.
        :param pkg: _AudioContentPackage object
        :param target: installation target; default is '/'"""
        fp = self.ctx.args.destination.joinpath(pkg.download_path)
        return installer(fp, target=target)

    def unpack_aar(self, pkg: "_AudioContentPackage", **kwargs) -> bool:
        """Unpack an '.aar' archive to a specific destination.
        Uses '-d' to set the directory the archive will be unpacked into, '-i' is the input archive file.
        :param pkg: _AudioContentPackage object"""
        fp = self.ctx.args.destination.joinpath(pkg.download_path)
        p = aa("extract", "-d", str(self.ctx.args.library_path), "-i", str(fp))

        return p.returncode == 0
