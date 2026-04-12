"""Mixin for content downloading."""

# type: ignore [attr-defined]
# mypy: disable-error-code="attr-defined"
import logging
import subprocess

from pathlib import Path
from typing import Optional, TYPE_CHECKING

# from .._config import ServerBases, VersionConsts
from .._config import VersionConsts
from ..utils.package_utils import pkg_is_signed_by_apple

if TYPE_CHECKING:
    from ..models.package import _AudioContentPackage


log = logging.getLogger(__name__)

DEFAULT_ARGS = [
    "--fail",
    "--retry",
    "3",  # max of 3 retries
    "--retry-delay",
    "5",  # max no of seconds between retry
    "--retry-all-errors",  # retry on any error, requires '--retry'
    "--connect-timeout",
    "20",  # allow up to 20sec before a connection timesout
    "--speed-limit",
    "300",  # when a transfer is slower than this (bytes per second), abort
    "--speed-time",
    "30",  # number of seconds that is used for '--speed-limit'
    "--progress-bar",  # progress bar output as %, conforms to env["COLUMNS"] value
    "--create-dirs",  # create any dirs required to save the file
    "--remote-time",  # attempt to use the timestamp of the remote file if present and use for local time
]


def curl(url: str, *args, **kwargs) -> Optional[subprocess.CompletedProcess]:
    """Subprocess the '/usr/bin/curl' binary.
    :param url: url"""
    new_args = ("-L", "--user-agent", VersionConsts.USER_AGENT, *(str(arg) for arg in args), url)
    cmd = ["/usr/bin/curl", *new_args]
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("encoding", "utf-8")
    kwargs.setdefault("check", True)  # raise exception when curl itself has returncode != 0

    try:
        log.debug("Subprocessing '%s'", " ".join(cmd))
        return subprocess.run(cmd, **kwargs)
    except subprocess.CalledProcessError as e:
        stdout = str(e.stdout or "").strip()
        stderr = str(e.stderr or "").strip()
        msg = "Subprocess '%s' exited with returncode %s; stdout=%s, stderr=%s"
        log.debug(msg, " ".join(cmd), e.returncode, stdout, stderr)
        return


class DownloadMixin:
    """Holds methods for downloading package content."""

    def download_pkg(self, pkg: "_AudioContentPackage") -> bool:
        """Download the audio content package; return True/False on success/failure.
        :param pkg: _AudioContentPackage object"""
        url, dest = self.generate_url_and_dest(pkg)
        cmd_args = list(DEFAULT_ARGS)  # copy we can use locally

        if self.ctx.args.quiet:
            cmd_args.append("--silent")

        if self.ctx.args.no_proxy:
            cmd_args.extend(["--noproxy", "'*'"])

        # use existing package if present when in deploy mode
        if self.ctx.deploy_mode and not self.ctx.args.dry_run:
            if self.pkg_is_downloaded(dest, state="existing", skip_sig_check=False):
                return True

        curl(url, *cmd_args, "-o", str(dest), capture_output=False, env=self.ctx.env)

        if pkg.is_legacy:
            return self.pkg_is_downloaded(dest, state="completed", skip_sig_check=self.ctx.args.skip_sig_check)

        return self.pkg_is_downloaded(dest, state="completed", skip_sig_check=True)

    def generate_url_and_dest(self, pkg: "_AudioContentPackage") -> tuple[str, Path]:
        """Generate the correct URL for the package file and the destination to save it.
        :param pkg: _AudioContentPackage object"""
        if "{path}" in self.ctx.server:
            url = self.ctx.server.format(path=pkg.download_path)
        else:
            url = f"{self.ctx.server}/{pkg.download_path}"

        return (url, self.ctx.args.destination.joinpath(pkg.download_path))

    def download_failed_log_msg(self, pkg: "_AudioContentPackage") -> str:
        """Returns a message string in the event the package failed to download; includes a message about installation
        will not occur if deploying the package.
        :param pkg"""
        pfx = f"\t{pkg.name} was not downloaded"
        msg = f"{pfx}{', the file will not be installed' if self.ctx.deploy_mode else ''}"
        return msg

    def pkg_is_downloaded(self, fp: Path, *, state: str, skip_sig_check: bool) -> bool:
        """Use heuristics to determine if the file is a completed download.
        :param fp: Path object
        :param state: 'completed', or 'existing'; used to indicate a completed/existing download when logging"""
        if self.ctx.args.dry_run or (self.ctx.args.skip_sig_check and self.ctx.download_mode):
            log_msg = "Package is downloaded because dry-run=%s or (skip_sig_check=%s and download_mode=%s)"
            log_args = (self.ctx.args.dry_run, self.ctx.args.skip_sig_check, self.ctx.download_mode)
            log.debug(log_msg, *log_args)
            return True

        file_exists = fp.exists()
        pfx = f"Heuristics test for {state} download (file exists "

        if not file_exists:
            return False

        if skip_sig_check:
            log.debug("%s only): %s", pfx, file_exists)
            return True

        signed = pkg_is_signed_by_apple(fp) is True
        log.debug("%s+signature check): exists=%s, signed=%s", pfx, file_exists, signed)
        return signed
