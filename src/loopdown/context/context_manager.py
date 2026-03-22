"""Orchestration through context management."""
import argparse
import logging

from collections.abc import Mapping
from functools import cached_property
from os import environ
from shutil import get_terminal_size
from uuid import uuid4

from ._server_mixin import ServerResolverMixin
from ._system_info_mixin import SystemInfoMixin
from .._config import VersionConsts

log = logging.getLogger(__name__)


class ContextManager(
    ServerResolverMixin,
    SystemInfoMixin,
):
    """Context manager for orchestration use."""

    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args

    @cached_property
    def env(self) -> Mapping:
        """Returns the OS environment variables, adding the calculated TTY width."""
        current_env = environ.copy()
        current_env["COLUMNS"] = self.tty_width

        return current_env

    @cached_property
    def deploy_mode(self) -> bool:
        """In deploy mode."""
        return self.args.action == "deploy"

    @cached_property
    def download_mode(self) -> bool:
        """In download mode."""
        return self.args.action == "download"

    @cached_property
    def loopdown_version(self) -> str:
        """loopdown version"""
        return f"{VersionConsts.NAME.value} v{VersionConsts.VERSION.value}"

    @cached_property
    def os_platform(self) -> str:
        """OS platform."""
        return f"OS platform: {VersionConsts.PLATFORM.value}"

    @cached_property
    def os_vers(self) -> str:
        """OS version"""
        return self.get_os_vers()

    @cached_property
    def python_version(self) -> str:
        """Python version."""
        return f"Python {VersionConsts.PYTHON_VERSION.value}"

    @cached_property
    def run_uid(self) -> str:
        """Run UID for logging."""
        return str(uuid4()).upper()

    @cached_property
    def server(self) -> str:
        """The resolved server the content will be sourced from when downloading."""
        return self.resolve_server()

    @cached_property
    def tty_width(self) -> str:
        """The current TTY column width."""
        step, fallback, min_width, max_width, right_offset = 10, (80, 24), 80, 100, 50
        actual = get_terminal_size(fallback=fallback)
        columns = min(((actual.columns // step) * step), max_width) - right_offset

        if columns < 0:
            columns = min_width

        return str(columns)

    def log_context_in_debug(self) -> None:
        """Log various context values."""
        log.debug("Run %s with argument namespace: %s", self.loopdown_version, self.args)
        log.debug("Basic host details: %s (%s), %s", self.os_vers, self.os_platform, self.python_version)
        log.debug("Using content server: '%s'", self.server)
