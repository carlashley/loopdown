import logging
import sys

from collections.abc import Sequence
from functools import cached_property
from typing import Optional

from ..models.package import AudioContentPackage
from ..models.size import Size
from ..utils.installer_utils import installer
from ..utils.system_utils import disk_space_available, resolve_installed_applications

log = logging.getLogger(__name__)
filelog = logging.getLogger("loopdown.fileonly")


class InstallMixin:
    """Installation helper methods mixin for LoopdownContext class."""

    @cached_property
    def installed_apps(self) -> tuple:
        """Applications installed on the system for which content can be downloaded/installed."""
        return tuple(resolve_installed_applications())

    def _has_space_available(self, packages: Sequence[AudioContentPackage]) -> Optional[tuple[bool, Size, Size]]:
        """Check enough space is available to proceed with download or download and install."""
        available_space = Size(disk_space_available())
        req, opt = self._generate_bucket_stats(packages)
        total = req + opt
        tot_reqd_space = total.down + total.inst
        has_space = available_space > tot_reqd_space

        if not self.args.dry_run and not has_space:
            log.error(f"Insufficient space available: {tot_reqd_space} required, {available_space} available.")
            sys.exit(2)

        log.debug("Passes free space check: %s required, %s available", tot_reqd_space, available_space)
        return (has_space, tot_reqd_space, available_space)

    def _install(self, pkg: AudioContentPackage) -> bool:
        """Install the package.
        :param f: path to the package file"""
        return installer(str(self.args.destination.joinpath(pkg.download_path)))
