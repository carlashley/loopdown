import json
import logging
import subprocess

from collections.abc import Mapping
from typing import Optional

from ..consts.cache_consts import CacheLocatorConsts

log = logging.getLogger(__name__)


def asset_cache_locator() -> Optional[dict]:
    """Subprocess the '/usr/bin/AssetCacheLocatorUtil' binary."""
    cmd = ["/usr/bin/AssetCacheLocatorUtil", "--json"]

    try:
        p = subprocess.run(cmd, capture_output=True, check=True)
    except subprocess.CalledProcessError as e:
        log.debug(f"{' '.join(cmd)} exited with returncode {e.returncode}; stdout: {e.stdout}, stderr: {e.stderr}")

        return None

    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError as e:
        log.debug(f"JSON decode error while resolving caching server: {str(e)}")

        return None


def is_server_healthy(
    server: Mapping, *, minimum_ranking: Optional[int] = None, ignore_favoured: Optional[bool] = False
) -> bool:
    """Determine if the caching server is healthy based on its rank value exceeding the minimum ranking
    value, if the 'healthy' value is True, and where 'favored' exists, if that is True.
    :param minimum_ranking: optional integer between a minimum/maximum value to indicate the server meets
                            our needs; default value is 0
    :param ignore_favoured: optional bool to override the 'favored' value; currently not an arg that can
                            be provided from command line but here in case there are special circumstances
                            where it might be needed; recommend explicitly specifying cache server in
                            environments with complex cache server structuring"""
    minimum_ranking = minimum_ranking or CacheLocatorConsts.DEFAULT_PREFERRED_RANK

    if (
        not isinstance(minimum_ranking, int)
        or not CacheLocatorConsts.MIN_RANK <= minimum_ranking <= CacheLocatorConsts.MAX_RANK
    ):
        raise ValueError(
            f"{minimum_ranking=} should be an integer between {CacheLocatorConsts.MIN_RANK} and "
            f"{CacheLocatorConsts.MAX_RANK}"
        )

    healthy = server.get("healthy", False)
    favoured = server.get("favored", None) if not ignore_favoured else True
    rank = server.get("rank", None)

    if healthy:
        if favoured is None:
            return rank >= minimum_ranking

        return favoured and rank >= minimum_ranking

    return False


def extract_cache_server(
    *,
    source: str = "system",
    minimum_ranking: Optional[int] = None,
    ignore_favoured: Optional[bool] = False,
    scheme_pfx: Optional[str] = None,
) -> Optional[str]:
    """Extract the cache server details if one is discoverable.
    :param source: preferred source; default is 'system'
    :param minimum_ranking: preferred rank of the server; default is 0
    :param scheme_pfx: default scheme to prefix the host address with; default is 'http://'"""
    scheme_pfx = scheme_pfx or CacheLocatorConsts.DEFAULT_SERVER_SCHEME

    if source not in CacheLocatorConsts.VALID_SOURCES:
        raise ValueError(f"{source=} is invalid; choose from {CacheLocatorConsts.VALID_SOURCES}")

    data = asset_cache_locator()

    if data is None:
        log.debug("no data found to extract caching server values from")
        return None

    source_meta = data["results"].get(source, {})

    try:
        all_servers = source_meta["saved servers"]["all servers"]
    except KeyError as e:
        log.debug(f"error parsing all server data: {str(e)}")
        return None

    # not sure how 'rank' is supposed to work, have seen some AssetCacheLocatorUtil results
    # show an identical rank value for servers in 'all_servers'; sort anyway on the chance it does;
    # presumption is lowest is better
    if len(all_servers) > 1:
        all_servers = sorted(all_servers, key=lambda s: s["rank"])

    for server in all_servers:
        if is_server_healthy(server, minimum_ranking=minimum_ranking, ignore_favoured=ignore_favoured):
            hostport = server["hostport"]
            url = f"{scheme_pfx}{hostport}"  # typically doesn't have the scheme prefixed

            return url

    return None
