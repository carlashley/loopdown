"""Package utils."""

import logging
import plistlib
import subprocess

from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)


def pkgutil(*args, **kwargs) -> Optional[subprocess.CompletedProcess]:
    """Subprocess the '/usr/sbin/pkgutil' binary.
    :param *args: argument sequence passed to the binary
    :param **kwargs: keyword arguments passed to the subprocess.run call"""
    cmd = ["/usr/sbin/pkgutil", *args]
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("check", True)

    try:
        log.debug("Subprocessing '%s'", " ".join(cmd))
        return subprocess.run(cmd, **kwargs)
    except subprocess.CalledProcessError as e:
        stdout = (e.stdout.decode() if isinstance(e.stdout, bytes) else e.stdout or "").strip()
        stderr = (e.stderr.decode() if isinstance(e.stderr, bytes) else e.stderr or "").strip()
        msg = "Subprocess '%s' exited with returncode %s; stdout=%s, stderr=%s"
        log.debug(msg, " ".join(cmd), e.returncode, stdout, stderr)
        return None


def get_pkg_info(pkg_id) -> Optional[dict]:
    """Subprocess the '/usr/sbin/pkgutil' binary.
    :param pkg_id: package id"""
    p = pkgutil("--pkg-info-plist", pkg_id)

    if p is None:
        return None

    # pylint: disable=broad-exception-caught
    try:
        return plistlib.loads(p.stdout)
    except plistlib.InvalidFileException:
        log.error("Error reading package information for '%s'", pkg_id)
        return None
    except Exception as e:  # blow up for logging on any unknown exception type
        log.error("Unknown error occurred when reading package information for '%s': %s", pkg_id, str(e))
        return None
    # pylint: enable=broad-exception-caught


def check_pkg_signature(fp: Path) -> Optional[tuple[int, tuple[str, ...]]]:
    """Check the signature of a package file.
    :param fp: file path"""
    p = pkgutil("--check-signature", str(fp), encoding="utf-8", check=False)

    if p is None:
        return None

    stdout = tuple(ln.strip() for ln in p.stdout.strip().splitlines()) if p.stdout else None
    stderr = p.stderr.strip() if p.stderr else None

    if p.returncode != 0 and not stdout:
        log.debug("Error checking signature for '%s': %s", str(fp), stderr)
        return (p.returncode, (stderr,) if stderr else ())

    if stdout is None:
        return None

    return (p.returncode, stdout)


def pkg_is_signed_by_apple(fp: Path, *, pfx: str = "Status: ") -> Optional[bool]:
    """Verify the signature status is 'signed Apple Software' of a package with 'pkgutil'.
    Note: in testing a partial download, it appears that 'pkgutil --check-signature' will
    return status lines:
        - 'package is invalid (checksum did not verify)' incomplete file/invalid file
        - 'Could not open package: test.txt' not a package file
        - 'Status: signed Apple Software
           Notarization: trusted by the Apple notary service'

    Therefore it appears somewhat feasible that this can be used to ensure the package is
    downloaded correctly.

    :param fp: package file path"""
    pkg_signature = check_pkg_signature(fp)

    if pkg_signature is None:
        return None

    returncode, output = pkg_signature
    status = next((ln.removeprefix(pfx) for ln in output if ln.startswith(pfx)), None)
    is_apple_software = (returncode == 0 and status is not None and "signed apple" in status.casefold())
    log_args = (str(fp), status, pfx, is_apple_software)
    log.debug("Signature status of '%s': status='%s' == pfx='%s': is_apple_software='%s'", *log_args)

    return is_apple_software
