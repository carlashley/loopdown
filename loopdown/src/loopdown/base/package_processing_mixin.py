import json
import logging
import shutil
import sys

from collections.abc import Generator, Iterator, Mapping, Sequence
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import lru_cache
from typing import Any

from ..consts.package_consts import PackageConsts
from ..models.application import Application
from ..models.package import AudioContentPackage
from ..models.size import BucketStats
from ..utils.date_utils import datetimestamp
from ..utils.threading_utils import max_workers_for_threads

log = logging.getLogger(__name__)
filelog = logging.getLogger("loopdown.fileonly")


def _generate_audio_package_dataclass_obj(data: Mapping) -> AudioContentPackage:
    """Generate an instance of the 'AudioContentPackage' dataclass from data.
    :param data: mapping object the dataclass will be derived from"""
    values = {mapped_attr: data.get(attr) for attr, mapped_attr in PackageConsts.DATACLASS_ATTRS_MAP.items()}
    obj = AudioContentPackage(**values)  # type: ignore[arg-type]

    return obj


class PackageProcessingMixin:
    """Package processing helper methods mixin for LoopdownContext class."""

    def _add_pkg_for_processing(self, pkg: AudioContentPackage) -> bool:
        """Determine if a package should be added for processing based on the following criteria:
            - download only
            - required arg provided and the package is required
            - optional arg provided and the package is optional
        :param pkg: AudioContentPackage instance"""
        required = pkg.mandatory and self.args.required
        optional = not pkg.mandatory and self.args.optional

        return required or optional

    def _additional_pkg_info(self, pkg: AudioContentPackage) -> str:
        """Additional package info for logging to stdout during download/install processing."""
        msg = f"{pkg.download_size} download"

        if not self.download_mode:
            return f"{msg}, {pkg.installed_size} installed"

        return msg

    def _cleanup(self) -> None:
        """Clean up working directory after processing."""
        if not self.args.dry_run:
            if not self.download_mode and self.args.destination.exists():
                try:
                    shutil.rmtree(self.args.destination, ignore_errors=False)
                    log.info("Cleaned up working directory")
                except Exception as e:
                    log.warning(f"Failed to clean up working directory: {str(e)}")
                    sys.exit(2)

    def _dry_run_summary(self, packages: Sequence[AudioContentPackage]) -> None:
        """Summary information provided at end of dry run."""
        if not self.args.dry_run:
            return

        req, opt = self._generate_bucket_stats(packages)
        want_opt = bool(self.args.optional)
        want_req = bool(self.args.required)

        def _log_bucket(label: str, stats: BucketStats) -> None:
            msg = f"{label} packages: {stats.count} ({stats.down} download"
            sfx = f", {stats.inst} installed)" if self.deploy_mode else ")"
            log.info("%s%s", msg, sfx)

        if want_req:
            _log_bucket("Required", req)

        if want_opt:
            _log_bucket("Optional", opt)

        total = req + opt
        _log_bucket("Total", total)

    def _gather_packages_concurrently(self, apps: Sequence[Application]) -> list[AudioContentPackage]:
        """Process all apps concurrently and union the package sets."""
        merged_by_id: dict[str, AudioContentPackage] = {}

        for _, pkgs in self._iter_packages_concurrently(apps):
            self._merge_packages_by_id(merged_by_id, pkgs)

        merged_list = list(merged_by_id.values())
        sorted_merged = sorted(merged_list, key=lambda pkg: (not pkg.mandatory, pkg.download_size, pkg.name))
        self.audit_debug(
            "packages gathered for shared deployment/download",
            data={"packages": [pkg.as_dict() for pkg in sorted_merged]},
        )

        return sorted_merged

    def _gather_packages_concurrently_by_app(
        self, apps: Sequence[Application], *, pkg_json: bool
    ) -> Generator[dict[str, Any], None, None]:
        """Gather packages concurrently by app. Return a dictionary {"app_name": tuple(packages)}.
        :param apps: sequence of Application instances
        :param pkg_json: iterate over packages and convert to dictionary instance so it can be converted easily
                         to JSON when '--scan' is applied"""
        for app, pkgs in self._iter_packages_concurrently(apps):
            # defensive: enforce mandatory precedence even if pkgs came from elsewhere
            by_id: dict[str, AudioContentPackage] = {}
            self._merge_packages_by_id(by_id, list(pkgs))
            pkgs = set(by_id.values())

            if pkg_json:
                new_pkgs: list[dict] = [pkg.as_dict() for pkg in pkgs]
            else:
                new_pkgs: list[AudioContentPackage] = sorted(  # type: ignore[no-redef]
                    list(pkgs), key=lambda pkg: (not pkg.mandatory, pkg.download_size, pkg.name)
                )

            out = {
                "name": app.name,
                "short_name": app.short_name,
                "packages": new_pkgs,
            }
            self.audit_debug(f"packages gathered for {app.short_name}", data=out)

            yield out

    def _generate_bucket_stats(self, packages: Sequence[AudioContentPackage]) -> tuple[BucketStats, BucketStats]:
        """Normalizer intermediary for '_generate_bucket_stats_cache'. Converts 'packages' to tuple.
        :param packages: sequence of AudioContentPackage"""
        return self._generate_bucket_stats_cache(tuple(packages))

    @lru_cache(maxsize=2)
    def _generate_bucket_stats_cache(
        self, packages: tuple[AudioContentPackage, ...]
    ) -> tuple[BucketStats, BucketStats]:
        """Generate bucket stats for use.
        :param packages; tuple of AudioContentPackage's; must be tuple in order for 'lru_cache' to be able to hash
                         it"""
        req = BucketStats()
        opt = BucketStats()
        want_opt = bool(self.args.optional)
        want_req = bool(self.args.required)

        for pkg in packages:
            if want_req and pkg.mandatory:
                req.add(pkg)
            elif want_opt and not pkg.mandatory:
                opt.add(pkg)

        return (req, opt)

    def _generate_scan_json_output(self, apps: Sequence[Application]) -> None:
        """Generate JSON output for the '--scan' usage scenario."""
        out = {
            "mode": "scan",
            "generated_at": datetimestamp(),
            "apps": [app_pkgs for app_pkgs in self._gather_packages_concurrently_by_app(apps, pkg_json=True)],
            "_version": "1",  # not loopdown version!
        }

        json.dump(out, sys.stdout, ensure_ascii=False, default=str)

    def _iter_app_packages(self, app: Application) -> set[AudioContentPackage]:
        """Read + filter one app's packages; returns a set for easy unioning.
        :param app: Application instance"""
        pkgs_meta = app.packages

        # early abort
        if pkgs_meta is None:
            return set()

        # dict used to store packages by preferred mandatory=True
        by_id: dict[str, AudioContentPackage] = {}

        for pkg_data in pkgs_meta.values():
            pkg = _generate_audio_package_dataclass_obj(pkg_data)

            if not self.download_mode and pkg.is_installed and not self.args.force_install:
                continue

            if not self._add_pkg_for_processing(pkg):
                continue

            # testing preferred state
            existing = by_id.get(pkg.package_id)

            if existing is None:
                by_id[pkg.package_id] = pkg
            else:
                by_id[pkg.package_id] = self._prefer_mandatory_pkg(existing, pkg)

        return set(by_id.values())

    def _iter_packages_concurrently(
        self, apps: Sequence[Application]
    ) -> Iterator[tuple[Application, set[AudioContentPackage]]]:
        """Process all apps concurrently and union the package sets."""
        # threads help here because the hot path is filesystem I/O + plist parsing; using a conservative default
        max_workers = max_workers_for_threads()

        with ThreadPoolExecutor(max_workers=max_workers) as ex:
            futures = {ex.submit(self._iter_app_packages, app): app for app in apps}

            for future in as_completed(futures):
                app = futures[future]

                try:
                    pkgs = future.result()
                    log.info(f"Processed content for {app.name}")
                    yield (app, pkgs)
                except Exception:
                    # definitely want any failures here to blow up; makes debugging very hard if they don't
                    raise

    def _merge_packages_by_id(
        self,
        merged: dict[str, AudioContentPackage],
        incoming: Sequence[AudioContentPackage] | set[AudioContentPackage],
    ) -> None:
        """Merge packages into 'merged' keyed by 'package_id', applying mandatory precedence."""
        for pkg in incoming:
            if pkg.package_id not in merged:
                merged[pkg.package_id] = pkg
                continue

            merged[pkg.package_id] = self._prefer_mandatory_pkg(merged[pkg.package_id], pkg)

    def _prefer_mandatory_pkg(
        self, existing: AudioContentPackage, candidate: AudioContentPackage
    ) -> AudioContentPackage:
        """Returns the preferred package instance for a given 'package_id'.
        Precedence determined by:
            1: mandatory=True always wins over mandatory=False"""
        if existing.mandatory or candidate.mandatory:
            # return whichever is mandatory (or existing if both mandatory)
            return existing if existing.mandatory else candidate

        return existing  # fallback to existing
