import logging
import plistlib
import subprocess

from pathlib import Path
from typing import Optional

from packaging import version as vers

log = logging.getLogger(__name__)


def pkgutil(*args, **kwargs) -> subprocess.CompletedProcess:
    """Subprocess the '/usr/sbin/pkgutil' binary.
    :param *args: argument sequence passed to the binary
    :param **kwargs: keyword arguments passed to the subprocess.run call"""
    cmd = ["/usr/sbin/pkgutil", *args]
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("check", True)

    try:
        return subprocess.run(cmd, **kwargs)
    except subprocess.CalledProcessError as e:
        log.debug(f"{' '.join(cmd)} exited with returncode {e.returncode}; stdout: {e.stdout}, stderr: {e.stderr}")
        return None


def pkg_info(pkg_id, **kwargs) -> Optional[dict]:
    """Subprocess the '/usr/sbin/pkgutil' binary.
    :param pkg_id: package id
    :param **kwargs: keyword arguments passed to the subprocess.run call"""
    p = pkgutil("--pkg-info-plist", pkg_id)

    try:
        return plistlib.loads(p.stdout)
    except plistlib.InvalidFileException:
        log.error(f"Error reading package information for '{pkg_id}'")
        return None
    except Exception as e:
        log.error(f"Unknown error occurred when reading package information for '{pkg_id}': {str(e)}")
        return None


def check_pkg_signature(fp: Path, **kwargs) -> Optional[tuple[int, str]]:
    """Check the signature of a package file.
    :param fp: file path"""
    p = pkgutil("--check-signature", str(fp), encoding="utf-8", check=False)
    stdout = tuple(ln.strip() for ln in p.stdout.strip().splitlines()) if p.stdout else None
    stderr = p.stderr.strip() if p.stderr else None

    if not p.returncode == 0 and not stdout:
        log.debug(
            f"Error checking signature for '{str(fp)}': {stderr}")

        return (p.returncode, stderr)

    return (p.returncode, stdout)


def installed_pkg_version(pkg_id: str) -> vers.Version:
    """Get the installed version of a package, from the package id.
    Uses '/usr/sbin/pkgutil --pkg-info-plist pkg_id'.
    :param pkg_id: package id; for example 'com.apple.MAContent.LegacyJamPack6'"""
    version = "0.0.0"  # default version indicates no package info found/not installed
    data = pkg_info(pkg_id)

    if data is not None:
        version = data.get("pkg-version", "0.0.0")

    return vers.parse(version)


def found_sentinel_files(files: list[str]) -> bool:
    """Sentinel files found at expected locations. This is an extra check to ensure the package content actuall
    exists as output from the 'pkginfo' only confirms the package WAS installed and not IS installed.
    This method is used in the models.package.AudioContentPackage dataclass.
    :param files: a list of string values representing each sentinel file to test"""
    files_exist = any(Path(f).expanduser().exists() for f in files)

    return files_exist


def installed_version_satisfies_required_version(*, installed: vers.Version, required: vers.Version) -> bool:
    """Using prefix-floor semantics, ensures the 'installed' version satisfies the 'required' version.
    For example, installed=2.1.0.0.20251224, required=2.1; installed satisfies required.
    This method is used in the models.package.AudioContentPackage dataclass, but can be used elsewhere.
    :param installed: installed version
    :param required: required version"""
    req = required.release

    if not req:
        # required is something odd; treat as "no minimum"
        return True

    inst = installed.release

    # if installed has fewer components than required, pad with zeros (rare, but safe)
    if len(inst) < len(req):
        inst_prefix = inst + (0,) * (len(req) - len(inst))
    else:
        inst_prefix = inst[: len(req)]

    result = inst_prefix >= req

    return result


def pkg_is_signed_apple_software(fp: Path, *, pfx: str = "Status: ") -> Optional[bool]:
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
    returncode, output = check_pkg_signature(fp)
    status = next((ln.removeprefix(pfx) for ln in output if ln.startswith(pfx)), None)
    is_apple_software = (returncode == 0 and status == "signed Apple Software")
    log.debug(f"Signature status of '{str(fp)}': {status=} == {pfx=}: {is_apple_software=}")

    return is_apple_software
