import logging
import os

from collections.abc import Mapping
from functools import cached_property
from pathlib import Path
from typing import Optional

from ..consts.apple_enums import AppleConsts
from ..models.package import AudioContentPackage
from ..utils.cache_utils import extract_cache_server
from ..utils.normalizers import normalize_caching_server_url
from ..utils.package_utils import pkg_is_signed_apple_software
from ..utils.request_utils import curl, CURL_DOWNLOAD_ARGS
from ..utils.system_utils import get_tty_column_width
from ..utils.validators import validate_url

log = logging.getLogger(__name__)
filelog = logging.getLogger("loopdown.fileonly")


class DownloadMixin:
    """Download helper methods mixin for LoopdownContext class."""

    @cached_property
    def os_env(self) -> Mapping:
        """Cached copy of OS environment variables for curl use."""
        env = os.environ.copy()
        env["COLUMNS"] = self.tty_column_width

        return env

    @cached_property
    def server(self) -> Optional[str]:
        """Return the server in use."""
        host = self._resolve_server()
        log.debug(f"Resolved server to: '{host}'")

        return host

    @cached_property
    def tty_column_width(self) -> str:
        """Get the TTY column width."""
        return get_tty_column_width()

    def _download(self, pkg: AudioContentPackage) -> bool:
        """Download the package. Returns a bool value indicating success/failure of download.
        :param pkg: AudioContentPackage instance"""
        env = os.environ.copy()
        env["COLUMNS"] = self.tty_column_width
        args = list(CURL_DOWNLOAD_ARGS)
        url, dest = self._generate_url_and_dest(pkg)

        if self.args.quiet:
            args.append("--silent")

        curl(url, *args, "-o", str(dest), capture_output=False, env=env)

        if not self._has_been_downloaded(pkg, state="completed"):
            return False

        audit_payload = {"url": url, "downloaded_to": str(dest)}
        self.audit(f"downloaded {dest.name}", data=audit_payload)
        return True

    def _has_been_downloaded(self, pkg: AudioContentPackage, *, state: str) -> bool:
        """Use a subprocessed call to 'pkgutil' and other heuristics to determine if the file is a completed
        download.
        :param fp: path object
        :param state: used in the log to indicate a completed download or existing download, value should be
                      either 'completed' or 'existing'"""
        fp = self.args.destination.joinpath(pkg.download_path)
        exists = fp.exists()
        signed = pkg_is_signed_apple_software(fp) or False
        downloaded = exists and signed
        log.debug(f"Heuristics test for {state} download appears to pass: {exists=} and {signed=} == {downloaded}")

        return downloaded

    def _generate_url_and_dest(self, pkg: AudioContentPackage) -> tuple[str, Path]:
        """Generate the url and destination path for a given AudioContentPackage object.
        :param pkg: AudioContentPackage instance"""
        url = f"{self.server}/{pkg.download_path}"
        dest = self.args.destination.joinpath(pkg.download_path)

        return (url, dest)

    def _resolve_server(self) -> Optional[str]:
        """Server that will be used. Returns value in order of:
        - mirror server argument
        - caching server argument
        - defaults to Apple content server"""
        apple_url = AppleConsts.CONTENT_SOURCE.value

        # only ever retrieve content from the authorative source when downloading content
        if self.download_mode:
            return apple_url

        # return mirror value first so we can fall back to caching server lookup
        if self.args.mirror_server:
            return self.args.mirror_server

        # when the server is explicitly provided, return it first
        if self.args.cache_server is not None:
            return self.args.cache_server

        # attempt extracting a cache server
        host = extract_cache_server()

        # no cache server found, so report back with the Apple source
        if host is None:
            log.debug("Could not resolve a caching server")
            return apple_url

        err = validate_url(host, reqd_scheme="http", validate_port=True)

        if err:
            raise ValueError(err)

        return normalize_caching_server_url(host)
