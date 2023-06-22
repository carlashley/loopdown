import logging

from pathlib import Path
from typing import Optional
from .parsers import ParsersMixin
from .request import RequestMixin
from .utils import clean_up_dirs

logging.getLogger(__name__).addHandler(logging.NullHandler())


_license: str = "Apache License Version 2.0"
_script_name: str = "loopdown"
_version: str = "1.0.20230622"
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
        self.max_retries = max_retries
        self.max_retry_time_limit = max_retry_time_limit
        self.proxy_args = proxy_args
        self.log = log

        # Clean up before starting, just incase cruft is left over.
        self.cleanup_working_dirs()

        # This will/does contain all the mandatory/optional packages that will need to be processed
        # It's updated by 'ParserMixin.parse_packages'
        self.packages = {"mandatory": set(), "optional": set()}

    def __repr__(self):
        """String representation of class."""
        return self.parse_download_install_statement()

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
