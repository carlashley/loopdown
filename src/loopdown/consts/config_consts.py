"""Basic tool configuration constants."""

from pathlib import Path


class ConfigurationConsts:
    """Configuration constants. Not an enum."""

    DEFAULT_DOWNLOAD_DEST: Path = Path("/tmp/loopdown")
    DEFAULT_LOG_DIRECTORY: Path = Path("/Users/Shared/loopdown")
    DEFAULT_LOG_FILE = "loopdown.log"
