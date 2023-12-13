import logging

from pathlib import Path
from typing import Optional
from .parsers import ParsersMixin
from .request import RequestMixin
from .utils import clean_up_dirs

logging.getLogger(__name__).addHandler(logging.NullHandler())


_license: str = "Apache License Version 2.0"
_script_name: str = "loopdown"
_version: str = "1.0.20231213"
_version_string: str = f"{_script_name} v{_version}, licensed under the {_license}"


class Loopdown(ParsersMixin, RequestMixin):
    def __init__(
        self,
        dry_run: bool = False,
        mandatory: bool = False,
        optional: bool = False,
        apps: Optional[list[str]] = None,
        plists: Optional[str] = None,
        cache_server: Optional[str] = None,
        pkg_server: Optional[str] = None,
        create_mirror: Optional[Path] = None,
        install: Optional[bool] = False,
        force: Optional[bool] = False,
        silent: Optional[bool] = False,
        feed_base_url: Optional[str] = None,
        default_packages_download_dest: Optional[Path] = None,
        default_working_download_dest: Optional[Path] = None,
        default_log_directory: Optional[Path] = None,
        max_retries: Optional[int] = None,
        max_retry_time_limit: Optional[int] = None,
        proxy_args: Optional[list[str]] = None,
        log: Optional[logging.Logger] = None,
    ) -> None:
        self.dry_run = dry_run
        self.mandatory = mandatory
        self.optional = optional
        self.apps = apps
        self.plists = plists
        self.cache_server = cache_server
        self.pkg_server = pkg_server
        self.create_mirror = create_mirror
        self.install = install
        self.force = force
        self.silent = silent
        self.feed_base_url = feed_base_url
        self.default_packages_download_dest = default_packages_download_dest
        self.default_working_download_dest = default_working_download_dest
        self.default_log_directory = default_log_directory
        self.max_retries = max_retries
        self.max_retry_time_limit = max_retry_time_limit
        self.log = log

        # curl/request related arg lists
        self._useragt = ["--user-agent", f"{_script_name}/{_version_string}"]
        self._retries = ["--retry", self.max_retries, "--retry-max-time", self.max_retry_time_limit]
        self._noproxy = ["--noproxy", "*"] if self.cache_server else []  # for caching server
        self._proxy_args = proxy_args or []

        # Clean up before starting, just incase cruft is left over.
        self.cleanup_working_dirs()

        # This will/does contain all the mandatory/optional packages that will need to be processed
        # It's updated by 'ParserMixin.parse_packages'
        self.packages = {"mandatory": set(), "optional": set()}

    def __repr__(self):
        """String representation of class."""
        if self.has_packages:
            return self.parse_download_install_statement()
        else:
            msg = "No packages found; there may be no packages to download/install"
            suffix = None

            if self.apps:
                suffix = "application/s installed"
            elif self.plists:
                suffix = "metadata property list file/s found for processing"

            if suffix:
                return f"{msg} or no {suffix}"
            else:
                return f"{msg}"

    def process_metadata(self, apps_arg: list[str], plists_arg: list[str]) -> None:
        """Process metadata from apps/plists for downloading/installing"""
        if apps_arg:
            for app in apps_arg:
                source_file = self.parse_application_plist_source_file(app)

                if source_file and source_file.exists():
                    packages = self.parse_plist_source_file(source_file)
                    self.parse_packages(packages)

        if plists_arg:
            for plist in plists_arg:
                source_file = self.parse_plist_remote_source_file(plist)

                if source_file and source_file.exists():
                    packages = self.parse_plist_source_file(source_file)
                    self.parse_packages(packages)

    @property
    def has_packages(self) -> bool:
        """Test if metadata processing has yielded packages to download/install."""
        return (len(self.packages["mandatory"]) or len(self.packages["optional"])) > 0

    def sort_packages(self) -> set:
        """Sort packages into a single set."""
        return sorted(list(self.packages["mandatory"].union(self.packages["optional"])), key=lambda x: x.download_name)

    def download_or_install(self, packages: set) -> tuple[int, int]:
        """Perform the download or install, or output dry-run information as appropriate.
        :param packages: a set of package objects for downloading/installing"""
        errors, install_failures, total_packages = 0, [], len(packages)

        for package in packages:
            pkg = None
            counter = f"{packages.index(package) + 1} of {total_packages}"

            if package.status_ok:
                if self.dry_run:
                    prefix = "Download" if not self.install else "Download and install"
                elif not self.dry_run:
                    prefix = "Downloading" if not self.install else "Downloading and installing"
            else:
                prefix = "Package error"
                errors += 1

            self.log.info(f"{prefix} {counter} - {package}")

            if not self.dry_run:
                # Force download, Will not resume partials!
                if self.force and package.download_dest.exists():
                    package.download_dest.unlink(missing_ok=True)

                if package.status_ok:
                    pkg = self.get_file(package.download_url, package.download_dest, self.silent)

                if self.install and pkg:
                    self.log.info(f"Installing {counter} - {package.download_dest.name!r}")
                    installed = self.install_pkg(package.download_dest, package.install_target)

                    if installed:
                        self.log.info(f"  {package.download_dest} was installed")
                    else:
                        pkg_fp = package.download_dest
                        inst_fp = "/var/log/install.log"
                        log_fp = self.default_log_directory.joinpath("loopdown.log")
                        install_failures.append(package.download_dest.name)
                        self.log.error(
                            f"  {pkg_fp} was not installed; see '{inst_fp}' or '{log_fp}' for more information."
                        )

                    package.download_dest.unlink(missing_ok=True)

        return (errors, install_failures)

    def generate_warning_message(self, errors: int, total: int, threshold: float = 0.5) -> None:
        """Generate warning message if the number of package fetch errors exceeds a threshold value.
        :param errors: total number of errors when fetching packages
        :param total: total number of packages
        :param threshold: value to use for calculating the threshold; default is 0.5 (50%)"""
        return float(errors) >= float(total * threshold)

    def cleanup_working_dirs(self) -> None:
        """Clean up all working directories."""
        if self.default_working_download_dest.exists():
            clean_up_dirs(self.default_working_download_dest)

            if self.default_working_download_dest.exists():
                self.log.error(
                    f"Unable to delete {str(self.default_working_download_dest)!r}, please delete manually.",
                )

        if self.install and not self.dry_run and self.default_packages_download_dest.exists():
            clean_up_dirs(self.default_packages_download_dest)

            if self.default_packages_download_dest.exists():
                self.log.error(
                    f"Unable to delete ({str(self.default_packages_download_dest)!r}, please delete  manually)"
                )
