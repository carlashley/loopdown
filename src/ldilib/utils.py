"""Utils used in various package files."""
import shutil
import sys

from functools import partial
from os import geteuid
from pathlib import Path
from urllib.parse import urlparse
from .wrappers import sw_vers


class CachingServerMissingSchemeException(Exception):
    """Handle excpetiosn when the caching server scheme is missing."""

    pass


class CachingServerPortException(Exception):
    """Handle excpetiosn when the caching server url is missing a port value."""

    pass


class CachingServerSchemeException(Exception):
    """Handle excpetiosn when the caching server scheme is unsupported (https instead of http)."""

    pass


def bytes2hr(b: str | int, bs: int = 1024) -> str:
    """Converts bytes (file size/disk space) to a human readable value.
    :param b: byte value to convert
    :param bs: integer representation of blocksize for size calculation; default is 1024"""
    b, idx = int(b), 0
    suffixes: list[str] = ["B", "KB", "MB", "GB", "TB", "PB"]

    while b > bs and idx < len(suffixes):
        idx += 1
        b /= float(bs)

    return f"{b:.2f}{suffixes[idx]}"


def clean_up_dirs(fp: Path) -> None:
    """Clean up directory using recursive delete (ensure's directory contents are removed).
    :param fp: directory as a Path object"""
    shutil.rmtree(fp, ignore_errors=True)


def debugging_info() -> str:
    """Returns a string of useful debugging information."""
    sw_vers_kwargs = {"capture_output": True, "encoding": "utf-8"}
    pn = partial(sw_vers, *["--productName"], **sw_vers_kwargs)
    pv = partial(sw_vers, *["--productVersion"], **sw_vers_kwargs)
    bv = partial(sw_vers, *["--buildVersion"], **sw_vers_kwargs)
    mac_os_vers_str = f"{pn().stdout.strip()} {pv().stdout.strip()} ({bv().stdout.strip()})"

    return f"Debug info: {mac_os_vers_str}, Python {sys.version}"


def is_root() -> bool:
    """Is the effective user id root."""
    return geteuid() == 0


def validate_caching_server_url(url: str) -> None:
    """Validates that the caching server url contains the required scheme (http) and a port number
    :param url: caching server url"""
    url = urlparse(url)
    scheme, port = url.scheme, url.port

    # This order is important, because 'urlparse' doesn't handle circumstances where a scheme
    # is missing from a url, for example, if the url is example.org:22, the scheme becomes
    # example.org and the path becomes 22
    if not scheme or scheme and scheme not in ("http", "https"):
        raise CachingServerMissingSchemeException(f"Error: {url!r} is missing a valid scheme")

    if scheme and scheme == "https":
        raise CachingServerSchemeException(f"Error: {url!r} is using 'https', only 'http' schemes are supported")

    if not port:
        raise CachingServerPortException(f"Error: {url!r} does not contain a port number")
