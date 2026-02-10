"""Constants for AssetCacheLocator and related utils."""


class CacheLocatorConsts:
    """Locator constants. Not an enum."""

    VALID_SOURCES: tuple[str, str] = ("system", "current_user")
    DEFAULT_PREFERRED_RANK: int = 0
    DEFAULT_SERVER_SCHEME: str = "http://"
    VALID_SERVER_SCHEMES: tuple[str] = ("http://", )
    MIN_RANK: int = 0
    MAX_RANK: int = 1000
