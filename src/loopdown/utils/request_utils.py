import logging
import subprocess

from typing import Optional

from ..consts.version_enums import VersionConsts

log = logging.getLogger(__name__)

CURL_DOWNLOAD_ARGS = [
    "--fail",
    "--retry", "3",  # max of 3 retries
    "--retry-delay", "2",  # max no of seconds between retry
    "--retry-all-errors",  # retry on any error, requires '--retry'
    "--connect-timeout", "20",  # allow up to 20sec before a connection timesout
    "--speed-limit", "300",  # when a transfer is slower than this (bytes per second), abort
    "--speed-time", "30",  # number of seconds that is used for '--speed-limit'
    "--progress-bar",  # progress bar output as %, conforms to env["COLUMNS"] value
    "--create-dirs",  # create any dirs required to save the file
    "--remote-time",  # attempt to use the timestamp of the remote file if present and use for local time
]


def curl(url: str, *args, **kwargs) -> Optional[subprocess.CompletedProcess]:
    """Subprocess the '/usr/bin/curl' binary.
    :param url: url
    :param *args: argument sequence passed to the binary
    :param **kwargs: keyword arguments passed to the subprocess.run call"""
    cmd = ["/usr/bin/curl", "-L", "--user-agent", VersionConsts.USER_AGENT, *(str(arg) for arg in args), url]
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("encoding", "utf-8")
    kwargs.setdefault("check", True)  # raise exception when curl itself has returncode != 0

    try:
        return subprocess.run(cmd, **kwargs)
    except subprocess.CalledProcessError as e:
        log.debug(f"{' '.join(cmd)} exited with returncode {e.returncode}; stdout: {e.stdout}, stderr: {e.stderr}")

        return None
