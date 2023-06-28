"""Utils used in various package files."""
import argparse
import json
import shutil
import sys

from functools import partial
from os import geteuid
from pathlib import Path
from time import sleep
from typing import Any, Optional
from urllib.parse import urlparse

from .wrappers import assetcachelocatorutil, sw_vers


class CachingServerAutoLocateException(Exception):
    """Handle exceptions when the caching server cannot be automatically located."""

    pass


class CachingServerMissingSchemeException(Exception):
    """Handle exceptions when the caching server scheme is missing."""

    pass


class CachingServerPortException(Exception):
    """Handle exceptions when the caching server url is missing a port value."""

    pass


class CachingServerSchemeException(Exception):
    """Handle exceptions when the caching server scheme is unsupported (https instead of http)."""

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


def debugging_info(args: argparse.Namespace) -> str:
    """Returns a string of useful debugging information."""
    sw_vers_kwargs = {"capture_output": True, "encoding": "utf-8"}
    pn = partial(sw_vers, *["--productName"], **sw_vers_kwargs)
    pv = partial(sw_vers, *["--productVersion"], **sw_vers_kwargs)
    bv = partial(sw_vers, *["--buildVersion"], **sw_vers_kwargs)
    mac_os_vers_str = f"{pn().stdout.strip()} {pv().stdout.strip()} ({bv().stdout.strip()})"
    args = vars(args)
    args_str = ""

    for k, v in args.items():
        args_str = f"{args_str} '{k}'='{v}',".strip()

    return (
        f"OS Version: {mac_os_vers_str!r}; Executable: {sys.executable!r}; Python Version: {sys.version!r}"
        f" Arguments: {args_str}"
    )


def locate_caching_server(prefer: str = "system", rank_val: int = 1, retries: int = 3) -> Optional[str]:
    """Internal parser for determining a caching server value (url and port in the required format.
    This 'prefers' system data over current user data, and will always look for a 'saved server' with a ranking value
    of '1' by default.
    :param prefer: string representation of the preferred 'server' source from the binary result data, accepted values
                   are either 'system' or 'current user'; default is 'server'
    :param rank_val: integer value representing the rank value that is preferred; default value is '1'
    :param retries: integer value representing the maximum number of retries to find a caching server; when a client
                    has not initially seen a caching server the 'AssetCacheLocatorUtil' binary may return no result,
                    so a second scan should detect it"""
    prefer_map = {"system": "system", "user": "current user"}

    def is_favoured(s: dict[str, Any], r: int) -> bool:
        """Truth test for server favoured-ness.
        :param s: dictionary object representing server
        :param r: integer value representing rank value to test on"""
        favored, has_port, healthy = s.get("favored", False), s.get("hostport", False), s.get("healthy", False)
        matches_ranking = s.get("rank", -999) == r
        return favored and has_port and healthy and matches_ranking

    def _parse_servers_from_cache_locator(d: dict[str, Any]) -> Optional[dict[str, Any]]:
        """Internal parser to process server objects from the assetcachelocatorutil util result."""
        if d.get("results"):
            return d["results"].get(prefer_map[prefer])

    attempts = 0

    while attempts < retries:
        if not attempts == 0:
            sleep(2)

        p = assetcachelocatorutil(*["--json"], **{"capture_output": True, "encoding": "utf-8"})

        if p.returncode == 0 and p.stdout:
            data = json.loads(p.stdout.strip())
            saved_servers = _parse_servers_from_cache_locator(data).get("saved servers")

            if saved_servers:
                for server in saved_servers.get("all servers", []):
                    if is_favoured(server, rank_val):
                        hostport = server.get("hostport")
                        return f"http://{hostport}"
        attempts += 1

    raise CachingServerAutoLocateException("a caching server could not be found")


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
        raise CachingServerMissingSchemeException("missing http:// scheme prefix")

    if scheme and scheme == "https" or not scheme == "http":
        raise CachingServerSchemeException(f"invalid scheme {scheme}, only http:// scheme is supported")

    if not port:
        raise CachingServerPortException(f"no port number specified in {url!r}")
