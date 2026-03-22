"""Mixin for package statistics."""
# type: ignore [attr-defined]
# mypy: disable-error-code="attr-defined"
import logging

from collections.abc import Sequence
from typing import Optional, TYPE_CHECKING

from ..models.size import BucketStats

if TYPE_CHECKING:
    from ..models.package import AudioContentPackage


log = logging.getLogger(__name__)


def emit_bucket_log_msg(label: str, *, stats: BucketStats, deploy_mode: bool) -> None:
    """Emits a BucketStats message as a log event.
    :param label: label indicating the packages type; for example 'Required', 'Optional', or 'Total'
    :param stats: BucketStats object"""
    msg = f"{label} packages: {stats.count} ({stats.down} downloaded"
    sfx = f", {stats.inst} installed)" if deploy_mode else ")"
    log.info("%s%s", msg, sfx)


class BucketStatsMixin:
    """Holds methods for bucket stats."""
    _bucket_stats_cache: Optional[tuple[BucketStats, BucketStats]] = None

    def statistics_summary(self, pkgs: Sequence["AudioContentPackage"]) -> None:
        """Statistics summary.
        :param pkgs: sequence of AudioContentPackage object"""
        req, opt = self.generate_bucket_stats(pkgs)

        if bool(self.ctx.args.required):
            emit_bucket_log_msg("Required", stats=req, deploy_mode=self.ctx.deploy_mode)

        if bool(self.ctx.args.optional):
            emit_bucket_log_msg("Optional", stats=opt, deploy_mode=self.ctx.deploy_mode)

        emit_bucket_log_msg("Total", stats=req + opt, deploy_mode=self.ctx.deploy_mode)

    def generate_bucket_stats(self, pkgs: Sequence["AudioContentPackage"]) -> tuple[BucketStats, BucketStats]:
        """Generate and cache bucket stats for packages.
        :param pkgs: sequence of AudioContentPackage object"""
        if self._bucket_stats_cache is not None:
            return self._bucket_stats_cache

        req, opt = BucketStats(), BucketStats()

        for pkg in pkgs:
            if self.ctx.args.required and pkg.mandatory:
                req.add(pkg)
            elif self.ctx.args.optional and not pkg.mandatory:
                opt.add(pkg)

        self._bucket_stats_cache = (req, opt)
        return self._bucket_stats_cache
