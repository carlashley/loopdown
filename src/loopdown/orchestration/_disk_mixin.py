"""Mixin for disk space checks and cleanup operations."""

# type: ignore [attr-defined]
# mypy: disable-error-code="attr-defined"
import logging
import shutil
import sys

from functools import lru_cache
from shutil import disk_usage
from typing import Any

from ..models.size import BucketStats, Size


log = logging.getLogger(__name__)


@lru_cache(1)
def has_freespace(required: int, *, target: str = "/") -> tuple[bool, str, tuple[Any, ...]]:
    """Does the target have enough disk space. Because this is cached, 'required' param must be passed in as a
    hashable value; so it is converted back to a Size object for returning in the result.
    :param required: total required space (bytes) as integer
    :param target: the path of the disk being checked; default is '/' (path must be a mounted filesystem)"""
    available: int = Size(disk_usage(target).free)
    has_space = available.raw > required
    pass_fail = "passed" if has_space else "failed"
    log_msg = "Required disk space check: %s (%s required, %s available)"
    log_args = (pass_fail, Size(required), available)

    return (has_space, log_msg, log_args)


class DiskMixin:
    """Holds methods for disk space checks during installation and cleanup operations."""

    def calculate_required_space(self, esn: BucketStats, core: BucketStats, opt: BucketStats) -> Size:
        """Calculate the total required space for the given run mode (download/download+deploy).
        :param esn: essential packages BucketStats object
        :param core: core packages BucketStats object
        :param opt: optional packages BucketStats object"""
        total = esn.down + core.down + opt.down

        if self.ctx.deploy_mode:
            total += esn.inst + core.inst + opt.inst

        return total

    def cleanup_working_directory(self) -> None:
        """Clean up working directory after downloading and installing content. Does nothing in a dry-run."""
        if self.ctx.download_mode or self.ctx.args.dry_run:
            return

        if self.ctx.args.destination.exists():
            shutil.rmtree(self.ctx.args.destination)  # raises an error if one occurs
            log.info("Cleaned up working directory.")

    def exit_on_insufficient_freespace(self, required: Size, *, target: str = "/") -> None:
        """Test if there is enough freespace and exit if insufficient.
        :param required: total space required as a Size object
        :param target: the path of the disk being checked; default is '/' (path must be a mounted filesystem)"""
        has_space, log_msg, log_args = has_freespace(required.raw, target=target)

        if not has_space:
            log.error(log_msg, *log_args)
            sys.exit(2)

        log.debug(log_msg, *log_args)

    def emit_freespace_log_message(self, required: Size, *, target: str = "/") -> None:
        """Emits a log message indicating whether the free space check passed/failed and includes the requirement data.
        :param required: total space required as a Size object
        :param target: the path of the disk being checked; default is '/' (path must be a mounted filesystem)"""
        _, log_msg, log_args = has_freespace(required.raw, target=target)

        log.info(log_msg, *log_args)
