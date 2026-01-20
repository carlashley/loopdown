import posixpath

from pathlib import Path
from urllib.parse import urlparse, urlunparse
from typing import Optional

from ..consts.apple_enums import AppleConsts


def bytes2hr(v: str | int | float, *, bs: int = 1024) -> str:
    """Convert bytes size value to human readable value. For example: 10000000bytes > 10MB.
    :param v: value
    :param bs: block size; default is 1024"""
    v, idx = float(v), 0  # convert v to int, and set default index starting point
    suffixes = ("B", "KB", "MB", "GB", "TB", "PB")

    while v > bs and idx < len(suffixes) - 1:
        idx += 1
        v /= float(bs)

    return f"{v:.2f}{suffixes[idx]}"


def normalize_file_check_value(fc: str | list[str]) -> list[str]:
    """Normalize a string file check value into a list value."""
    if isinstance(fc, str):
        return [fc]

    return fc


def normalize_caching_server_url(url: str, *, content_source: Optional[str] = None) -> str:
    """Normalize paths in a URL and constructs the caching server URL.
    :param url: url to normalize"""
    content_source = content_source or urlparse(AppleConsts.CONTENT_SOURCE.value).netloc
    query = f"source={content_source}&sourceScheme=https"  # always force HTTPS before it's cached locally
    parsed = urlparse(url)
    path = posixpath.normpath(parsed.path)

    if path in (".", "/"):
        path = ""

    url = urlunparse(parsed._replace(scheme="http", path=path, query=query))

    return url


def normalize_package_download_path(name: str) -> str:
    """Normalize a package download path. Removes any '../lp10_ms3_content_xxxx' and resolves it to
    'lp10_ms3_content_xxxx'.
    :param name: package download name"""
    basename = Path(name).name

    if AppleConsts.PATH_2013.value in name:
        return f"{AppleConsts.PATH_2013.value}/{basename}"

    return f"{AppleConsts.PATH_2016.value}/{basename}"
