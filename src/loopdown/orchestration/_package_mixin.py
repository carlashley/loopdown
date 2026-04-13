"""Mixin for package processing."""

# type: ignore [attr-defined]
# mypy: disable-error-code="attr-defined"
import logging

from concurrent.futures import ThreadPoolExecutor
from os import cpu_count
from typing import Iterator

from ..models.application import Application
from ..models.package import _AudioContentPackage, AudioContentPackage, ModernAudioContentPackage

log = logging.getLogger(__name__)


AppPkgIterator = Iterator[tuple[Application, set[_AudioContentPackage]]]


def max_workers(*, max_cap: int = 16, def_cpu_count: int = 4, def_max_threads: int = 4) -> int:
    """Compute the maximum number of workers for thread based concurrency.
    :param max_cap: upper bound on the number of worker threads
    :param def_cpu_count: fallback CPU count if the OS cannot determine it, conservatively capped at 4
    :param def_max_threads: heuristic multiplier representing the maximum number of concurrent Python workers per
                            logical CPU"""
    return min(max_cap, (cpu_count() or def_cpu_count) * def_max_threads)


def prefer_essential_or_core_pkg(
    existing: _AudioContentPackage, candidate: _AudioContentPackage
) -> AudioContentPackage:
    """Prefer the AudioContentPackage that is mandatory over optional when two objects are identical.
    Returns the existing package if it is mandatory when either existing or candidate are mandatory otherwise
    return the candidate, otherwise falls back to returning the existing package."""
    if not existing.is_optional or not candidate.is_optional:
        return existing if not existing.is_optional else candidate

    return existing


def merge_packages_by_id(merged: dict[str, AudioContentPackage], incoming: set[AudioContentPackage]) -> None:
    """Merge packages into 'merged', keyed by 'package_id', applying mandatory precedence.
    :param merged: dictionary of already merged packages
    :param incoming: sequence of AudioContentPackage objects that will need to be merged with mandatory precedence"""
    for pkg in incoming:
        if pkg.package_id not in merged:
            merged[pkg.package_id] = pkg
            continue

        merged[pkg.package_id] = prefer_essential_or_core_pkg(merged[pkg.package_id], pkg)


class PackageProcessingMixin:
    """Holds methods for processing packages."""

    def add_package_for_processing(self, pkg: _AudioContentPackage) -> bool:
        """Determine if the package should be added for processing.
        :param pkg: _AudioContentPackage object"""
        essn = pkg.is_essential and self.ctx.args.essential
        core = pkg.is_core and self.ctx.args.core
        optn = pkg.is_optional and self.ctx.args.optional

        return essn or core or optn

    def gather_packages(self) -> list[AudioContentPackage]:
        """Gather all packages that will be processed, merges them so any mandatory packages win over any identical
        optional packages."""
        merged_by_id: dict[str, _AudioContentPackage] = {}

        for _, pkgs in self.iter_packages_concurrently():
            merge_packages_by_id(merged_by_id, pkgs)

        return sorted(
            list(merged_by_id.values()),
            key=lambda pkg: (not pkg.is_essential, not pkg.is_core, pkg.download_size, pkg.name),
        )

    def iter_packages_of_app(self, app: Application) -> set[_AudioContentPackage]:
        """Iterate over packages for an application and return a set of AudioContentPackage objects.
        :param app: Application object"""
        metadata = app.packages

        if metadata is None:
            return set()

        # track packages by preferred mandatory=True; aka mandatory always wins
        pkgs_by_id: dict[str, _AudioContentPackage] = {}

        for data in metadata.values():
            if bool(data.get("is_legacy", 1)):
                pkg = AudioContentPackage.from_dict(data)
            else:
                pkg = ModernAudioContentPackage.from_dict(data, args=self.ctx.args)

            if pkg is None:
                continue

            existing = pkgs_by_id.get(pkg.package_id)

            if self.ctx.deploy_mode and pkg.is_installed and not self.ctx.args.force:
                continue

            if not self.add_package_for_processing(pkg):
                continue

            if existing is None:
                pkgs_by_id[pkg.package_id] = pkg
            else:
                pkgs_by_id[pkg.package_id] = prefer_essential_or_core_pkg(existing, pkg)

        return set(pkgs_by_id.values())

    def iter_packages_concurrently(self) -> AppPkgIterator:
        """Process all packages for apps that will be processed."""
        with ThreadPoolExecutor(max_workers=max_workers()) as tpe:
            # submit a deterministic order and collect results in that same order so merge behaviour is
            # consistent regardless of thread scheduling (parity behaviour with Swift implementation).
            ordered = [(app, tpe.submit(self.iter_packages_of_app, app)) for app in self.apps_to_process]

            for app, future in ordered:
                try:
                    pkgs = future.result()
                    yield (app, pkgs)
                except Exception:
                    # force a blow up here; debugging is hard if this doesn't happen
                    raise

    def pkg_info_log_string(self, pkg: _AudioContentPackage) -> str:
        """Additional package information for logging to stdout during download/install processing.
        :param pkg: _AudioContentPackage object"""
        msg = f"{pkg.download_size} download"

        if self.ctx.deploy_mode:
            return f"{msg}, {pkg.installed_size} installed"

        return msg
