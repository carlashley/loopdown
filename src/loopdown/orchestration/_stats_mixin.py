"""Mixin for package statistics."""

# type: ignore [attr-defined]
# mypy: disable-error-code="attr-defined"
import logging

from collections.abc import Sequence
from typing import Optional, TYPE_CHECKING

from ..models.size import BucketStats

if TYPE_CHECKING:
    from ..models.package import _AudioContentPackage


log = logging.getLogger(__name__)

type EssentialCoreOptionalStats = tuple[BucketStats, BucketStats, BucketStats]


def emit_bucket_log_msg(label: str, *, stats: BucketStats, deploy_mode: bool) -> None:
    """Emits a BucketStats message as a log event.
    :param label: label indicating the packages type; for example 'Required', 'Optional', or 'Total'
    :param stats: BucketStats object"""
    msg = f"{label} packages: {stats.count} ({stats.down} downloaded"
    sfx = f", {stats.inst} installed)" if deploy_mode else ")"
    log.info("%s%s", msg, sfx)


class BucketStatsMixin:
    """Holds methods for bucket stats."""

    _bucket_stats_cache: Optional[EssentialCoreOptionalStats] = None

    def statistics_summary(self, pkgs: Sequence["_AudioContentPackage"]) -> None:
        """Statistics summary.
        :param pkgs: sequence of _AudioContentPackage object"""
        esn, core, opt = self.generate_bucket_stats(pkgs)

        if bool(self.ctx.args.essential):
            emit_bucket_log_msg("Essential", stats=esn, deploy_mode=self.ctx.deploy_mode)

        if bool(self.ctx.args.core):
            emit_bucket_log_msg("Core", stats=core, deploy_mode=self.ctx.deploy_mode)

        if bool(self.ctx.args.optional):
            emit_bucket_log_msg("Optional", stats=opt, deploy_mode=self.ctx.deploy_mode)

        emit_bucket_log_msg("Total", stats=esn + core + opt, deploy_mode=self.ctx.deploy_mode)

    def generate_bucket_stats(self, pkgs: Sequence["_AudioContentPackage"]) -> EssentialCoreOptionalStats:
        """Generate and cache bucket stats for packages.
        :param pkgs: sequence of _AudioContentPackage object"""
        if self._bucket_stats_cache is not None:
            return self._bucket_stats_cache

        esn, core, opt = BucketStats(), BucketStats(), BucketStats()

        for pkg in pkgs:
            if self.ctx.args.essential and pkg.is_essential:
                esn.add(pkg)
            elif self.ctx.args.core and pkg.is_core:
                core.add(pkg)
            elif self.ctx.args.optional and pkg.is_optional:
                opt.add(pkg)

        self._bucket_stats_cache = (esn, core, opt)
        return self._bucket_stats_cache
