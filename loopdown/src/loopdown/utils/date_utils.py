from datetime import datetime, timezone, tzinfo
from functools import lru_cache
from typing import Optional

import tzlocal


@lru_cache(maxsize=1)
def get_effective_localzone() -> tzinfo:
    """Return the system local timezone (cached for speedy reference). Fallback to UTC if the local timezone is
    non determinable."""
    try:
        tz = tzlocal.get_localzone()

        # ensure tz behaves like a tzinfo
        if tz is None:
            raise RuntimeError("tzlocal returned None")

        return tz
    except Exception:
        return timezone.utc


def get_local_tz_offset_and_sanitized_name() -> tuple[int, str]:
    """Return (offset_seconds, tz_abbreviation). Fall back to UTC if local timezone cannot be determined."""
    tz = get_effective_localzone()
    now = datetime.now(tz)
    offset_td = tz.utcoffset(now)
    offset_seconds = int(offset_td.total_seconds()) if offset_td else 0
    tz_name = tz.tzname(now) or "UTC"

    return (offset_seconds, tz_name)


def datetimestamp(t: Optional[int | float] = None, *, as_utc: bool = False, timespec: str = "milliseconds") -> str:
    """Return an ISO-8601 timestamp in UTC or local time (default is to use local time, but falls back to UTC) with
    offset included.
    Returns 'YYYY-mm-ddTHH:MM:SS.fff+HH:MM' formatted string.
    :param t: optional int/float value of unix epoch time
    :param as_utc: timestamp returned in UTC format; default False returns timestamp in local timezone
    :param timespec: the specification applied to the timestamp, for example 'milliseconds' generates a timestamp
                     with three microseconds; default is 'milliseconds'"""
    tz = timezone.utc if as_utc else get_effective_localzone()
    dt = (
        datetime.fromtimestamp(t, tz=tz)
        if isinstance(t, (int, float))
        else datetime.now(tz=tz)
    )

    return dt.isoformat(timespec=timespec)
