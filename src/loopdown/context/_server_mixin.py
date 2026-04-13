"""Mixin for server resolution."""

# type: ignore [attr-defined]
# mypy: disable-error-code="attr-defined"
import json
import logging
import subprocess

from datetime import datetime, timezone
from urllib.parse import urlencode, urlparse, urlunparse
from time import sleep
from typing import Any, Callable, Optional, TypeVar

from .._config import ServerBases
from ..utils.validators import validate_url

log = logging.getLogger(__name__)

CONTENT_SOURCE = ServerBases.BASE
T = TypeVar("T")


def _retry(fn: Callable[[], Optional[T]], *, max_retry: int = 3, pause: float = 1.0) -> Optional[T]:
    """Retries a function up to a specified maximum number of times, pauses for a specified number of
    seconds between attempts.
    :param fn: function to retry
    :maram max_retry: maximum retries
    :param pause: number of seconds to pause"""
    for attempt in range(1, max_retry + 1):
        result = fn()

        if result is not None:
            return result

        if attempt < max_retry:
            log.debug("Attempt %s/%s returned None, retrying in %ss", attempt, max_retry, pause)
            sleep(pause)

    log.debug("All %s attempts returned None", max_retry)
    return None


def assetcachelocator(**kwargs) -> Optional[dict[str, Any]]:
    """Subprocess '/usr/bin/AssetCacheLocatorUtil'."""
    cmd = ["/usr/bin/AssetCacheLocatorUtil", "--json"]
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("check", True)

    try:
        log.debug("Subprocessing '%s'", " ".join(cmd))
        p = subprocess.run(cmd, **kwargs)
    except subprocess.CalledProcessError as e:
        stdout = str(e.stdout.decode() if isinstance(e.stdout, bytes) else e.stdout or "").strip()
        stderr = str(e.stderr.decode() if isinstance(e.stderr, bytes) else e.stderr or "").strip()
        msg = "Subprocess '%s' exited with returncode %s; stdout=%s, stderr=%s"
        log.debug(msg, " ".join(cmd), e.returncode, stdout, stderr)
        return None

    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError as e:
        log.debug("JSON decoding error while resolving cache server: %s", str(e))
        return None


def cache_server_is_candidate(data: dict[str, Any], *, pref_rank: Optional[int] = None) -> bool:
    """Determine if the caching server is a candidate based on several heuristics.
    :param data: output of subprocessed 'AssetCacheLocatorUtil'
    :param pref_rank: preferred server ranking; default is 0"""
    min_rank, max_rank = 0, 1000
    pref_rank = pref_rank or 0

    if not isinstance(pref_rank, int) or not min_rank <= pref_rank <= max_rank:
        raise ValueError(f"{pref_rank=} must be an integer between/equal to {min_rank} and {max_rank}")

    hlt = bool(data.get("healthy", False))
    rnk = data.get("rank")
    fav = data.get("favored")
    vld = data.get("advice", {}).get("validUntil")
    now = datetime.now(tz=timezone.utc)

    # server data contains a 'validUntil' UTC timestamp which indicates that a cache server
    # can expire, so we probably need to consider this validity
    if vld:
        log.debug("Candidate cache server is valid until: '%s'", vld)
        try:
            vld = datetime.strptime(vld, "%Y-%m-%d %H:%M:%S %z")
            valid = vld > now
        except ValueError as e:
            log.debug("Error converting 'validUntil' to native datetime (ignoring value): %s", str(e))
            valid = False
    else:
        valid = False

    if hlt is True:
        if valid and fav is True:
            # if server is favoured; return this first
            log.debug("Candidate cache server is healthy: %s, ranked: %s, favoured: %s", hlt, rnk, fav)
            return rnk >= pref_rank
        elif valid:
            # if server is valid, but not favoured, return second
            log.debug("Candidate cache server is healthy: %s, ranked: %s", hlt, rnk)
            return rnk >= pref_rank
        else:
            # finally return if not favoured and not valid, but is healthy
            log.debug("Candidate cache server is healthy: %s", hlt)
            return rnk >= pref_rank

    return False


def extract_cache_server(*, source: str = "system", pref_rank: Optional[int] = None) -> Optional[str]:
    """Attempt to extract cache server details from the output of subprocessed 'AssetCacheLocatorUtil'
    :param source: select either 'system' or 'current_user'; default is 'system'
    :param pref_rank: preferred server ranking; default is 0"""
    if source not in ("system", "current_user"):
        raise ValueError(f"{source=} invalid; must be either 'system' or 'current_user'")

    metadata = _retry(assetcachelocator)

    if metadata is None:
        log.debug("No metadata to extract cache server value from")
        return None

    try:
        # not sure of the distinction between 'refreshed servers' and 'all servers' in the output
        # but 'shared caching' is the specific caching type required in either of the metadata for those, so only
        # return servers that are in the 'shared caching' object contained in relevant metadata
        servers = metadata["results"][source]["saved servers"]["shared caching"]
        log.debug("Found saved servers in 'AssetCacheLocatorUtil' output")
    except KeyError as e:
        log.debug("Error extracting discovered cache servers: %s", str(e))
        return None

    # backup catch in case servers is None
    if servers is None:
        return None

    if len(servers) > 1:
        servers = sorted(servers, key=lambda s: s["rank"])

    for server in servers:
        if cache_server_is_candidate(server, pref_rank=pref_rank):
            return f"http://{server['hostport']}"

    return None


def generate_cache_server_string(s: str) -> str:
    """Generates the URL for the caching server as a template string so '{path}' can be replaced by the package path.
    :param s: cache server value; for example 'http://ip:port'"""
    source = urlparse(CONTENT_SOURCE)
    query = urlencode({"source": source.netloc, "sourceScheme": source.scheme})
    url = urlparse(s)
    url = urlunparse(url._replace(scheme="http", path="{path}", query=query))

    return url


class ServerResolverMixin:
    """Holds methods for server resolution that will be mixed into the ContextManager class."""

    def resolve_server(self) -> str:
        """Resolve the server used as the content source. When a caching server is resolved, the string will include
        the path as a format-string placeholder ('{path}') that can be used to insert the correct package path.
        The resolution order is:
            - return the Apple content source when in download mode, this is the authoritative source
            - return a mirror server value only when it is supplied
            - return a cache server value (with '{path}' as a format-string placeholder) if a value for cache server
              is provided or the server is auto-discovered
            - return the Apple content source if everything else fails"""
        default_source = CONTENT_SOURCE

        # always return authoritative source in download mode; early abort if no mirror/cache server values provided
        if self.download_mode or (self.args.mirror_server is None and self.args.cache_server is None):
            log.debug("Resolved content source server as: '%s' (default)", default_source)
            return default_source

        if self.args.mirror_server is not None:
            log.debug("Resolved content source server as: '%s' (mirror)", self.args.mirror_server)
            return self.args.mirror_server

        if self.args.cache_server not in ["auto", None]:
            host = self.args.cache_server
            log.debug("Resolved content source server as: '%s' (cache, user provided)", self.args.cache_server)
        else:
            host = extract_cache_server()
            log.debug("Resolved content source server as: '%s' (cache, auto-discover)", self.args.cache_server)

            if host is None:
                log.debug("Resolved content source server as: '%s' (default, cache discovery failed)", default_source)
                return default_source

        err = validate_url(host, reqd_scheme="http", validate_port=True)

        if err is not None:
            log.debug("Resolved content source server as: '%s' (cache, auto-discovery) exception: %s", host, err)
            raise ValueError(err)

        return generate_cache_server_string(host)
