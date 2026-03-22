"""Mixin for package processing."""
# type: ignore [attr-defined]
# mypy: disable-error-code="attr-defined"
import logging

from concurrent.futures import ThreadPoolExecutor, as_completed
from os import cpu_count
from typing import Iterator

from ..models.application import Application
from ..models.package import AudioContentPackage

log = logging.getLogger(__name__)


AppPkgIterator = Iterator[tuple[Application, set[AudioContentPackage]]]


def max_workers(*, max_cap: int = 16, def_cpu_count: int = 4, def_max_threads: int = 4) -> int:
    """Compute the maximum number of workers for thread based concurrency.
    :param max_cap: upper bound on the number of worker threads
    :param def_cpu_count: fallback CPU count if the OS cannot determine it, conservatively capped at 4
    :param def_max_threads: heuristic multiplier representing the maximum number of concurrent Python workers per
                            logical CPU"""
    return min(max_cap, (cpu_count() or def_cpu_count) * def_max_threads)


def prefer_mandatory_pkg(existing: AudioContentPackage, candidate: AudioContentPackage) -> AudioContentPackage:
    """Prefer the AudioContentPackage that is mandatory over optional when two objects are identical.
    Returns the existing package if it is mandatory when either existing or candidate are mandatory otherwise
    return the candidate, otherwise falls back to returning the existing package."""
    if existing.mandatory or candidate.mandatory:
        return existing if existing.mandatory else candidate

    return existing


def merge_packages_by_id(merged: dict[str, AudioContentPackage], incoming: set[AudioContentPackage]) -> None:
    """Merge packages into 'merged', keyed by 'package_id', applying mandatory precedence.
    :param merged: dictionary of already merged packages
    :param incoming: sequence of AudioContentPackage objects that will need to be merged with mandatory precedence"""
    for pkg in incoming:
        if pkg.package_id not in merged:
            merged[pkg.package_id] = pkg
            continue

        merged[pkg.package_id] = prefer_mandatory_pkg(merged[pkg.package_id], pkg)


class PackageProcessingMixin:
    """Holds methods for processing packages."""

    def add_package_for_processing(self, pkg: AudioContentPackage) -> bool:
        """Determine if the package should be added for processing.
        :param pkg: AudioContentPackage object"""
        reqd = pkg.mandatory and self.ctx.args.required
        optn = not pkg.mandatory and self.ctx.args.optional

        return reqd or optn

    def gather_packages(self) -> list[AudioContentPackage]:
        """Gather all packages that will be processed, merges them so any mandatory packages win over any identical
        optional packages."""
        merged_by_id: dict[str, AudioContentPackage] = {}

        for _, pkgs in self.iter_packages_concurrently():
            merge_packages_by_id(merged_by_id, pkgs)

        return sorted(list(merged_by_id.values()), key=lambda pkg: (not pkg.mandatory, pkg.download_size, pkg.name))

    def iter_packages_of_app(self, app: Application) -> set[AudioContentPackage]:
        """Iterate over packages for an application and return a set of AudioContentPackage objects.
        :param app: Application object"""
        metadata = app.packages

        if metadata is None:
            return set()

        # track packages by preferred mandatory=True; aka mandatory always wins
        pkgs_by_id: dict[str, AudioContentPackage] = {}

        for data in metadata.values():
            pkg = AudioContentPackage.from_dict(data)

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
                pkgs_by_id[pkg.package_id] = prefer_mandatory_pkg(existing, pkg)

        return set(pkgs_by_id.values())

    def iter_packages_concurrently(self) -> AppPkgIterator:
        """Process all packages for apps that will be processed."""
        with ThreadPoolExecutor(max_workers=max_workers()) as tpe:
            futures = {tpe.submit(self.iter_packages_of_app, app): app for app in self.apps_to_process}

            for future in as_completed(futures):
                app = futures[future]

                try:
                    pkgs = future.result()
                    yield (app, pkgs)
                except Exception:
                    # force a blow up here; debugging is hard if this doesn't happen
                    raise

    def pkg_info_log_string(self, pkg: AudioContentPackage) -> str:
        """Additional package information for logging to stdout during download/install processing.
        :param pkg: AudioContentPackage object"""
        msg = f"{pkg.download_size} download"

        if self.ctx.deploy_mode:
            return f"{msg}, {pkg.installed_size} installed"

        return msg
