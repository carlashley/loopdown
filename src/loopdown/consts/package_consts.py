"""Package constants."""


class PackageConsts:
    """Constant class for required package attributes. Not an enum."""

    DATACLASS_ATTRS_MAP: dict[str, str] = {
        "DownloadName": "download_name",
        "PackageID": "package_id",
        "DownloadSize": "download_size",
        "FileCheck": "file_check",
        "InstalledSize": "installed_size",
        "IsMandatory": "mandatory",
        "PackageVersion": "version",
    }
