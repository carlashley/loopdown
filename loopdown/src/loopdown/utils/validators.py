from typing import Optional
from urllib.parse import urlparse


def validate_url(url: str, *, reqd_scheme: str, validate_port: Optional[bool] = False) -> Optional[str]:
    """Validate a caching server URL has the required components."""
    fmt_sfx = f"(expected {reqd_scheme}://host{':port' if validate_port else ''})"
    parsed = urlparse(url)

    def generate_err_msg(msg: str, *, sfx: Optional[str] = None) -> str:
        sfx = sfx or ""
        return f"'{url}' {msg} {sfx}".strip()

    if (parsed.scheme or "").lower() != reqd_scheme:
        return generate_err_msg("invalid scheme", sfx=fmt_sfx)

    if parsed.username or parsed.password:
        return generate_err_msg("user-info is not allowed", sfx=fmt_sfx)

    if validate_port:
        if not parsed.port:
            return generate_err_msg("missing port", sfx=fmt_sfx)

        if not isinstance(parsed.port, int) or not (1 <= parsed.port <= 65535):
            return generate_err_msg("port must be an integer between 1 and 65535")

    if parsed.query or parsed.fragment:
        return generate_err_msg("query/fragments not allowed", sfx=fmt_sfx)

    if parsed.path not in ("", "/"):
        return generate_err_msg("path not allowed", sfx=fmt_sfx)

    return None
