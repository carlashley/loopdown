"""Orchestration class providing all methods to execute download and/or install of content."""
import logging

from functools import cached_property
from typing import Optional

from ._apps_mixin import ApplicationDiscoveryMixin
from ._disk_mixin import DiskMixin
from ._download_mixin import DownloadMixin
from ._installation_mixin import InstallationMixin
from ._package_mixin import PackageProcessingMixin
from ._stats_mixin import BucketStatsMixin
from ..context import ContextManager
from ..models.application import Application

log = logging.getLogger(__name__)


class Orchestrate(
    ApplicationDiscoveryMixin,
    BucketStatsMixin,
    DiskMixin,
    DownloadMixin,
    InstallationMixin,
    PackageProcessingMixin,
):
    """Orchestrates dry runs, downloading, and or installing."""

    def __init__(self, ctx: ContextManager) -> None:
        self.ctx = ctx

    @cached_property
    def apps_to_process(self) -> Optional[tuple[Application, ...]]:
        """Applications that will be processed."""
        return tuple(app for app in self.installed_apps if app.short_name in self.ctx.args.applications)

    @cached_property
    def installed_apps(self) -> tuple[Application, ...]:
        """Installed audio applications for which content can be processed."""
        return tuple(self.find_installed_apps())

    def process_content(self) -> None:
        """Process content for either download and/or installation (performing a dry-run if specified)."""
        log.info("Starting run %s", self.ctx.run_uid, extra={"file_only": True})
        self.ctx.log_context_in_debug()
        packages = self.gather_packages()

        if not packages:
            log.info("No packages found for processing; exiting.")
            return

        req, opt = self.generate_bucket_stats(packages)
        reqd_space = self.calculate_required_space(req, opt)
        self.exit_on_insufficient_freespace(reqd_space)

        tot = len(packages)
        pad = len(str(tot))

        for idx, pkg in enumerate(packages, start=1):
            sfx = self.pkg_info_log_string(pkg)
            log.info(f"{idx:>{pad}} of {tot} - {pkg} ({sfx})")

            if self.ctx.args.dry_run:
                continue

            downloaded = self.download_pkg(pkg)

            if not downloaded:
                log.error(self.download_failed_log_msg(pkg))
                continue

            if not self.ctx.deploy_mode:
                continue

            installed = self.install_pkg(pkg)

            if not installed:
                log.error(f"\tinstall failed for {pkg}")
            else:
                log.info(f"\tinstalled {pkg}")
                pkg.unlink(self.ctx.args.destination, missing_ok=True)

        if self.ctx.args.dry_run:
            self.statistics_summary(packages)
            self.emit_freespace_log_message(reqd_space)

        self.cleanup_working_directory()
        log.info("Finished run %s", self.ctx.run_uid, extra={"file_only": True})
