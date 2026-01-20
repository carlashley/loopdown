import json
import logging
import shutil
import subprocess

from collections.abc import Mapping
from functools import lru_cache
from typing import Generator, Optional

from ..consts.apple_enums import ApplicationConsts
from ..models.application import Application

log = logging.getLogger(__name__)


def disk_space_available(target: str = "/") -> int:
    """Disk space available. Returns an integer value.
    This uses 'shutil.disk_usage()' to get the _available_ space; this is not always going to match with
    actual 'free' space that a tool like 'diskutil' will report.
    Using the 'shutil.disk_usge()' method ensures the behaviour of this tool is in keeping with how various user
    facing apps like Finder, Installer.app, App Store, and other macOS API's report space."""
    return shutil.disk_usage(target).free


def get_tty_column_width(
    *,
    step: int = 10,
    fallback: tuple[int, int] = (100, 24),
    min_width: int = 80,
    max_width: int = 100,
    right_offset: int = 50,
) -> str:
    """Get the current TTY column width to the nearest 10's unit.
    :param step: intever value used to calculate down to the nearest column number
    :param fallback: tuple of integers representing fallback value
    :param min_width: integer value of minimum column width
    :param max_width: integer value of maximum column width not to exceed
    :param right_offset: number of columns to subtract from the right of the tty bounds"""
    columns = shutil.get_terminal_size(fallback=fallback).columns
    columns = min(((columns // step) * step), max_width) - right_offset

    if columns < 0:
        columns = min_width

    return str(columns)


@lru_cache(maxsize=1)
def sw_vers() -> Optional[str]:
    """Subprocess the '/usr/bin/sw_vers' binary. Result is cached."""
    cmd = ["/usr/bin/sw_vers"]

    try:
        p = subprocess.run(cmd, capture_output=True, encoding="utf-8", check=True)
    except subprocess.CalledProcessError as e:
        log.debug(f"{' '.join(cmd)} exited with returncode {e.returncode}; stdout: {e.stdout}, stderr: {e.stderr}")
        return None

    lines = p.stdout.strip().splitlines()
    vers_str = []

    for ln in lines:
        attr, val = [v.strip() for v in ln.split(":")]

        if attr == "BuildVersion":
            val = f"({val})"

        vers_str.append(val)

    return " ".join(vers_str)


def system_profiler(sp_type: str) -> Optional[dict]:
    """Subprocess the '/usr/sbin/system_profiler' binary.
    :param sp_type: system profiler data type; for example 'SPApplicationsDataType'"""
    cmd = ["/usr/sbin/system_profiler", "-json", "-detaillevel", "full", sp_type]

    try:
        p = subprocess.run(cmd, capture_output=True, check=True)
    except subprocess.CalledProcessError as e:
        log.debug(f"{' '.join(cmd)} exited with returncode {e.returncode}; stdout: {e.stdout}, stderr: {e.stderr}")
        return None

    try:
        return json.loads(p.stdout).get(sp_type)
    except json.JSONDecodeError as e:
        log.debug(f"JSON decode error while parsing system_profiler result: {str(e)}")

        return None


def resolve_installed_applications() -> Generator[Application, None, None]:
    """Resolves the installed applications that can be processed."""
    installed_apps = system_profiler("SPApplicationsDataType")

    if installed_apps is None:
        return  # keep mypy happy with a bare return

    def _generate_app_dataclass(app: Mapping) -> Application:
        """Generate a dataclass instance from an app mapping."""
        attrs = (("_name", "name"), ("version", "version"), ("path", "path"), ("lastModified", "last_modified"))
        data = {mapped_attr: app.get(attr) for attr, mapped_attr in attrs}

        return Application(**data)  # type: ignore[arg-type]

    for app in installed_apps:
        name = app.get("_name", "").casefold()

        if name not in ApplicationConsts.REAL_NAMES:
            continue

        yield _generate_app_dataclass(app)
