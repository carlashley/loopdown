from enum import Enum


class Version(Enum):
    VERSION: str = "1.0.0"
    BUILD: str = "2024-01-24"
    LICENSE: str = "Apache License Version 2.0"
    AUTHOR: str = "Carl Ashley"


class LoopdownMeta(Enum):
    VERSION_STR: str = (
        f"{Version.VERSION.value} Copyright 2023 {Version.AUTHOR.value} under the {Version.LICENSE.value}"
    )
    DESC: str = (
        "loopdown can be used to download, install, mirror, or discover information about the additional "
        "audio content that Apple provides for the audio editing/mixing software programs GarageBand, LogicPro X "
        ", and MainStage3."
    )
