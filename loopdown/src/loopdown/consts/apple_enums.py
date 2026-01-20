import re

from enum import StrEnum
from itertools import chain


# map 'short names' used in the command line to 'real name' alternatives in order of preference
_NAME_MAPPING: dict[str, tuple[str, ...]] = {
    "garageband": ("garageband", ),
    "logicpro": ("logic pro", "logic pro x"),
    "mainstage": ("mainstage", )
}


class AppleConsts(StrEnum):
    CONTENT_SOURCE = "https://audiocontentdownload.apple.com"
    PATH_2013 = "lp10_ms3_content_2013"
    PATH_2016 = "lp10_ms3_content_2016"


class ApplicationConsts:
    SHORT_NAMES: tuple[str, ...] = tuple(_NAME_MAPPING.keys())
    REAL_NAMES: tuple[str, ...] = tuple(chain.from_iterable(_NAME_MAPPING.values()))
    META_FILE_PATTERN: re.Pattern = re.compile(r"^[a-zA-Z]+[0-9]+\.plist$")
    RESOURCE_FILE_PATH: str = "Contents/Resources"

    # not used currently, but recorded for possible future use
    GARAGEBAND_BUNDLE_IDS: tuple[str, ...] = ("com.apple.garageband10", )
    LOGICPRO_BUNDLE_IDS: tuple[str, ...] = ("com.apple.logic10", "com.apple.logicpro10")
    MAINSTAGE_BUNDLE_IDS: tuple[str, ...] = ("com.apple.mainstage3", )
