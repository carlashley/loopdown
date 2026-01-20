import argparse
import logging

from functools import cached_property
from typing import Optional
from uuid import uuid4

from .audit_mixin import AuditLogMixin
from .base_mixin import ContextMixin

from ..models.package import AudioContentPackage
from ..utils.system_utils import get_tty_column_width, resolve_installed_applications

log = logging.getLogger(__name__)


class LoopdownContext(ContextMixin, AuditLogMixin):
    """Context holder for loopdown."""
    RUN_UID = str(uuid4()).upper()

    def __init__(self, args: argparse.Namespace) -> None:
        self.args: argparse.Namespace = args

    @cached_property
    def deploy_mode(self) -> bool:
        """Return boolean indicating 'self.args.action == "deploy"'"""
        return self.args.action == "deploy"

    @cached_property
    def download_mode(self) -> bool:
        """Return boolean indicating 'self.args.action == "download"'"""
        return self.args.action == "download"

    @cached_property
    def installed_apps(self) -> tuple:
        """Applications installed on the system for which content can be downloaded/installed."""
        return tuple(resolve_installed_applications())

    @cached_property
    def packages(self) -> Optional[list[AudioContentPackage]]:
        """Packages that will need to be processed."""
        apps_to_process = tuple(app for app in self.installed_apps if app.short_name in self.args.applications)

        # early abort if no apps
        if not apps_to_process:
            return None

        merged = self._gather_packages_concurrently(apps_to_process)
        return merged

    @cached_property
    def server(self) -> Optional[str]:
        """Return the server in use."""
        return self._resolve_server()

    @cached_property
    def tty_column_width(self) -> str:
        """Get the TTY column width."""
        return get_tty_column_width()

    def process_content(self) -> None:
        """Process content for applications."""
        packages = self.packages

        if not packages:
            log.info("No packages found for processing")
            return

        total_pkg_count = len(packages)
        width = len(str(total_pkg_count))

        # available space check
        has_space, tot_reqd_space, available_space = self._has_space_available(packages)  # type: ignore[misc]

        for idx, pkg in enumerate(packages, start=1):  # type: ignore[arg-type]
            pkg_log_sfx = self._additional_pkg_info(pkg)
            log.info(f"{idx:>{width}} of {total_pkg_count} - {pkg} ({pkg_log_sfx})")

            if self.args.dry_run:
                continue

            url, dest = self._generate_url_and_dest(pkg)
            downloaded = self._download(url, dest=dest)

            if self.download_mode or not downloaded:
                if not downloaded:
                    log.error(f"\t{pkg.name} was not downloaded")

                continue

            installed = self._install(dest)

            if installed:
                log.info(f"\tinstalled {pkg}")
                dest.unlink(missing_ok=True)
            else:
                log.error(f"\tinstall failed for {pkg}")

        if self.args.dry_run:
            self._dry_run_summary(packages)

        # cleanup
        self._cleanup()

    def scan(self) -> None:
        """Handles the '--scan' argument mode. Dumps a JSON string to stdout."""
        return self._generate_scan_json_output(self.installed_apps)
