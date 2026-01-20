import platform

from datetime import datetime
from enum import StrEnum

_C_SYMB = b'\xc2\xa9'.decode("utf-8")


class VersionConsts(StrEnum):
    AUTHOR = "Carl Ashley"
    COPYRIGHT = f"Copyright {_C_SYMB} {datetime.now().year}"
    NAME = "loopdown"
    PLATFORM = f"{platform.system()} {platform.release()}; {platform.machine()}"
    PYTHON_VERSION = platform.python_version()
    VERSION = "1.0.20251229"
    USER_AGENT = f"{NAME}/{VERSION} ({PLATFORM}; Python/{PYTHON_VERSION})"


class VersionInfo:
    COPYRIGHT_STRING = f"{VersionConsts.COPYRIGHT.value} {VersionConsts.AUTHOR.value}. All rights reserved"
    LICENSE_STRING = "Apache License Version 2.0 - http://www.apache.org/licenses/"
    VERSION_STRING = f"{VersionConsts.NAME.value} v{VersionConsts.VERSION.value}. {COPYRIGHT_STRING}."
