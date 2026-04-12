"""Configuration constants."""

import platform
import re

from datetime import datetime
from enum import StrEnum
from itertools import chain
from pathlib import Path


class ServerBases:
    LEGACY: str = "https://audiocontentdownload.apple.com"
    MODERN: str = "https://audiocontentdownload.apple.com/universal"


class ApplicationConsts:
    """Application constants. Not an enum."""

    NAME_MAPPING: dict[str, tuple[str, ...]] = {
        "garageband": ("garageband",),
        "logicpro": ("logic pro", "logic pro x"),
        "mainstage": ("mainstage",),
    }
    SHORT_NAMES: tuple[str, ...] = tuple(NAME_MAPPING.keys())
    REAL_NAMES: tuple[str, ...] = tuple(chain.from_iterable(NAME_MAPPING.values()))
    META_FILE_PATTERN: re.Pattern = re.compile(r"^[a-zA-Z]+[0-9]+\.plist$")
    RESOURCE_FILE_PATH: str = "Contents/Resources"

    # not used currently, but recorded for possible future use
    GARAGEBAND_BUNDLE_IDS: tuple[str, ...] = ("com.apple.garageband10",)
    LOGICPRO_BUNDLE_IDS: tuple[str, ...] = ("com.apple.logic10", "com.apple.logicpro10")
    MAINSTAGE_BUNDLE_IDS: tuple[str, ...] = ("com.apple.mainstage3",)


class ModernContentDownloadFeeds:
    ArtistProducerPacks: str = "ArtistProducerPacksContentDownloadFeed.rss"
    DrummersKitsPacks: str = "DrummersKitsPacksContentDownloadFeed.rss"
    InstrumentPacks: str = "InstrumentPacksContentDownloadFeed.rss"
    SoundPacks: str = "SoundPacksContentDownloadFeed.rss"
    StarterCompatibilityPacks: str = "StarterCompatibilityPacksContentDownloadFeed.rss"


class ConfigurationConsts:
    """Configuration constants. Not an enum."""

    DEFAULT_DOWNLOAD_DEST: Path = Path("/tmp/loopdown")
    DEFAULT_LOG_DIRECTORY: Path = Path("/Users/Shared/loopdown")
    DEFAULT_LOG_FILE = "loopdown.log"


_C_SYMB = b"\xc2\xa9".decode("utf-8")


class VersionConsts(StrEnum):
    """Version constants."""

    AUTHOR = "Carl Ashley"
    COPYRIGHT = f"Copyright {_C_SYMB} {datetime.now().year}"
    NAME = "loopdown"
    PLATFORM = f"{platform.system()} {platform.release()}; {platform.machine()}"
    PYTHON_VERSION = platform.python_version()
    VERSION = "2.0.20260327"
    USER_AGENT = f"{NAME}/{VERSION} ({PLATFORM}; Python/{PYTHON_VERSION})"


class VersionInfo:
    """Version info constants. Not an enum."""

    COPYRIGHT_STRING = f"{VersionConsts.COPYRIGHT.value} {VersionConsts.AUTHOR.value}. All rights reserved"
    LICENSE_STRING = "Apache License Version 2.0 - http://www.apache.org/licenses/"
    VERSION_STRING = f"{VersionConsts.NAME.value} v{VersionConsts.VERSION.value}. {COPYRIGHT_STRING}."
