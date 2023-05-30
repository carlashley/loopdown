"""Parsing mixin."""
import plistlib
import re
import sys

from packaging import version as vp
from pathlib import Path
from typing import Any, Optional
from urllib.parse import urljoin, urlparse

from .models import LoopDownloadPackage, Size

# from .request import get_file, get_headers, is_compressed, is_status_ok
from .utils import bytes2hr
from .wrappers import diskutil, installer, pkgutil


class ParsersMixin:
    """Parsers mixin."""

    APPLICATION_PATHS: dict[str, str] = {
        "garageband": "/Applications/GarageBand.app",
        "logicpro": "/Applications/Logic Pro X.app",
        "mainstage": "/Applications/MainStage 3.app",
    }

    # Create a set to store processed package names in to avoid duplication
    PROCESSED_PKGS = set()

    @property
    def mandatory_pkgs(self) -> set:
        """Return all mandatory packages."""
        return self.packages["mandatory"]

    @property
    def optional_pkgs(self) -> set:
        """Return all optional packages."""
        return self.packages["optional"]

    @property
    def mandatory_pkgs_download_size(self) -> int:
        return sum([pkg.download_size.filesize for pkg in self.mandatory_pkgs])

    @property
    def optional_pkgs_download_size(self) -> int:
        return sum([pkg.download_size.filesize for pkg in self.optional_pkgs])

    @property
    def mandatory_pkgs_installed_size(self) -> int:
        return sum([pkg.install_size.filesize for pkg in self.mandatory_pkgs])

    @property
    def optional_pkgs_installed_size(self) -> int:
        return sum([pkg.install_size.filesize for pkg in self.optional_pkgs])

    def include_package(self, p: LoopDownloadPackage) -> bool:
        """Determination check that a package needs to be included.
        :param p: instance of 'LoopDownloadPackage'"""
        return (self.create_mirror or not p.is_installed or self.force) and (
            (self.mandatory and p.is_mandatory) or (self.optional and not p.is_mandatory)
        )

    def parse_packages(self, pkgs: dict[str, dict[str, Any]]) -> None:
        """Parse packages from a source property list file representing audio content packages to download/install.
        :param pkgs: dictionary object representing package metadata"""
        index, max_p = 0, 11
        for name, pkg in pkgs.items():
            if index < max_p:
                if pkg["DownloadName"] not in self.PROCESSED_PKGS:
                    package = self.parse_package_for_attrs(pkg)

                    if self.include_package(package):
                        if package.is_mandatory:
                            append_to = "mandatory"
                        else:
                            append_to = "optional"

                        self.packages[append_to].add(package)
                index += 1

    def install_pkg(self, fp: Path, _target: str) -> bool:
        """Install a package.
        :param fp: package file path"""
        args = ["-dumplog", "-pkg", str(fp), "target", _target]
        kwargs = {"capture_output": True, "encoding": "utf-8"}
        p = installer(*args, **kwargs)

        self.log.debug(p.stdout.strip())
        self.log.warning(p.stderr.strip())

        return p.returncode == 0

    def all_files_installed(self, files: str | list[str]) -> bool:
        """Determines if all files that are used to determine a package is installed exist on the
        local filesystem.
        :param files: a string or list of string representations of all files that must be checked"""
        return all(Path(file).exists() for file in files)

    def fetch_remote_source_file(self, url: str, dest: Path) -> Optional[Path]:
        """Fetches a source file from a remote location. This is used to fetch the property list files
        that contain the package metadata for downloading/installing. This will always be a silent fetch
        request.
        :param url: url of remote resource to be fetched
        :param dest: destination path to save resource to"""
        return self.get_file(url, dest, silent=True)

    def has_enough_disk_space(self) -> bool:
        """Check the disk space available is sufficient for download/install operations."""
        dld_size = sum([self.mandatory_pkgs_download_size, self.optional_pkgs_download_size])
        inst_size = sum([self.mandatory_pkgs_installed_size, self.optional_pkgs_installed_size])

        if self.install:
            required_space = dld_size + inst_size
        else:
            required_space = dld_size

        args = ["info", "-plist", "/"]
        kwargs = {"capture_output": True}
        p = diskutil(*args, **kwargs)

        if p.returncode == 0:
            data = plistlib.loads(p.stdout)
            freespace = data.get("APFSContainerFree", data.get("FreeSpace"))
            has_freespace = freespace > required_space
            prefix = f"{bytes2hr(required_space)} space required, {bytes2hr(freespace)} available,"

            self.log.info(f"{prefix}, has enough space: {has_freespace}")
            return has_freespace
        else:
            self.log.error(f"Error performing disk space check: {p.stderr.decode('utf-8').strip()}")
            sys.exit(88)

    def local_pkg_vers_gt_remote_pkg_vers(self, vers_a: str | int | float, vers_b: str | int | float) -> bool:
        """Compares versions to determine if install or upgrade action must occur.
        :param vers_a: string representation of the current version of the package that is/is not installed
        :param vers_b: string representation of a version for the package that is being install/upgrade checked"""
        vers_a, vers_b = vp.parse(str(vers_a)), vp.parse(str(vers_b))

        return (vers_a > vers_b) or not (vers_a == vers_b)

    def package_is_installed(self, pkg_id: str, pkg_vers: str, _installed_pkg_vers: str = "0.0.0") -> bool:
        """Determine's if a package is installed based on whether there is a BOM found by 'pkgutil'.
        :param pkg_id: string representation of a pacakge id;
                       for example: 'com.apple.pkg.MAContent10_AssetPack_0718_EXS_MusicBox'
        :param pkg_vers: string representation of the package version to compare against the installed
                         version, if the package is installed"""
        args = ["--pkg-info-plist", pkg_id]
        kwargs = {"capture_output": True}
        p = pkgutil(*args, **kwargs)

        if p.returncode == 0:
            data = plistlib.loads(p.stdout)
            _installed_pkg_vers = data.get("pkg-version", "0.0.0")

            if _installed_pkg_vers == "0.0.0":
                return False
            else:
                return self.local_pkg_vers_gt_remote_pkg_vers(_installed_pkg_vers, pkg_vers)

    def parse_application_plist_source_file(
        self, app: str, _gp: str = "*.plist", _pattern: Optional[re.Pattern] = None
    ) -> Optional[Path]:
        """Parse an application directory for the property list file containing package metadata.
        :param app: string value of the app to parse data for; this is a simple representation of the
                    actual app, supported values are 'all'', 'garageband', 'logicpro', 'mainstage'"""
        _pattern = _pattern or re.compile(rf"{app}\d+.plist")
        files = sorted(
            [
                fp
                for fp in Path(self.APPLICATION_PATHS[app]).joinpath("Contents/Resources").rglob(_gp)
                if _pattern.search(fp.name)
            ],
            reverse=True,
        )

        if files and len(files) >= 1:
            return files[-1]

    def parse_plist_remote_source_file(self, plist: str) -> Optional[Path]:
        """Parse a remote source file, attempts to find it locally in an application folder first."""
        result = None
        if not plist.endswith(".plist"):
            plist = f"{plist}.plist"

        pattern = re.compile(rf"{plist}")

        for app, _ in self.APPLICATION_PATHS.items():
            result = self.parse_application_plist_source_file(app, _pattern=pattern)
            break

        if not result:
            url = urljoin(self.feed_base_url, plist)
            path = urlparse(url).path.removeprefix("/")
            dest = self.default_working_download_dest.joinpath(path)
            result = self.fetch_remote_source_file(url, dest)

        return result

    def parse_caching_server_url(self, url: str, server: str) -> str:
        """Formats a url into the correct format required for pulling a file through Apple content caching
        server/s.
        Note: HTTPS is not supported by Apple caching server, so url's will be converted from HTTPS to HTTP.
        :param url: url to be formatted
        :param server: the caching url; this must be in the format of 'http://example.org:port'"""
        url = urlparse(url.replace("https", "http"))
        path, netloc = url.path, url.netloc

        return f"{server}{path}?source={netloc}"

    def parse_download_install_statement(self) -> str:
        """Parse the total size of packages to be downloaded, how many are mandatory, optional."""
        mnd_count, opt_count = len(self.mandatory_pkgs), len(self.optional_pkgs)
        tot_count = sum([mnd_count, opt_count])

        mnd_dld_size, opt_dld_size = self.mandatory_pkgs_download_size, self.optional_pkgs_download_size
        tot_dld_size = bytes2hr(sum([mnd_dld_size, opt_dld_size]))
        mnd_dld_size = bytes2hr(mnd_dld_size)
        opt_dld_size = bytes2hr(opt_dld_size)

        mnd_inst_size, opt_inst_size = self.mandatory_pkgs_installed_size, self.optional_pkgs_installed_size
        tot_inst_size = bytes2hr(sum([mnd_inst_size, opt_inst_size]))
        mnd_inst_size = bytes2hr(mnd_inst_size)
        opt_inst_size = bytes2hr(opt_inst_size)

        mnd_opt_statement = []

        if self.install:
            total_statement = f"Total packages: {tot_count} ({tot_dld_size} download, {tot_inst_size} installed)"
            mnd_dld_str = f"{mnd_count} mandatory packages ({mnd_dld_size} download, {mnd_inst_size} installed)"
            opt_dld_str = f"{opt_count} optional packages ({opt_dld_size} download, {opt_inst_size} installed)"
        else:
            total_statement = f"Total packages: {tot_count} ({tot_dld_size} download)"
            mnd_dld_str = f"{mnd_count} mandatory packages ({mnd_dld_size} download)"
            opt_dld_str = f"{opt_count} optional packages ({opt_dld_size} download)"

        if self.mandatory and len(self.packages["mandatory"]) > 0:
            mnd_opt_statement.append(f"\n  - {mnd_dld_str}")

        if self.optional and len(self.packages["optional"]) > 0:
            mnd_opt_statement.append(f"\n  - {opt_dld_str}")

        mnd_opt_statement = "".join(mnd_opt_statement)
        return f"{total_statement}{mnd_opt_statement}"

    def parse_package_for_attrs(self, p: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
        """Parse a package dictionary object out into a tuple of two dictionaries representing
        the download package and the install package.
        Used to create a dataclass representation of the download package attributes and install
        package attributes.
        :param p: dictionary object representing a package"""
        result = {}  # ensure this attribute is always present; default is False anyway
        pkg_attrs = {
            "IsMandatory": "is_mandatory",
            "DownloadName": "download_name",
            "DownloadSize": "download_size",
            "PackageID": "package_id",
            "FileCheck": "file_check",
            "InstalledSize": "install_size",
            "PackageVersion": "package_vers",
        }

        for k, v in p.items():
            # Ensure string values have no bad trailing characters, some package id's do
            if isinstance(v, str):
                v = v.strip()

            # Ensure the 'file_check' attribute has a list of strings
            if k == "FileCheck" and isinstance(v, str):
                v = [v]

            if k in pkg_attrs:
                attr = pkg_attrs[k]
                result[attr] = v

        result.update(self.parse_updated_package_attr_vals(result))
        self.PROCESSED_PKGS.add(result.get("download_name"))  # Track already processed packages
        package = LoopDownloadPackage(**result)

        return package

    def parse_plist_source_file(self, fp: Path) -> Optional[dict[Any, Any]]:
        """Parse a property list source file for the package metadata dictionary.
        :param fp: file path"""
        with fp.open("rb") as f:
            data = plistlib.load(f)

            if data:
                return data.get("Packages", {})

    def parse_updated_package_attr_vals(self, pkg: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
        """Parse updated attribute values for a download package dictionary.
        :param pkg: the download package dictionary"""
        dest_base = self.create_mirror or self.default_packages_download_dest
        name = pkg["download_name"]
        size_fallback = pkg["download_size"]
        url = self.parse_package_url_from_name(name, self.pkg_server or self.cache_server)
        pkg_path = urlparse(url).path

        pkg["download_url"] = self.parse_caching_server_url(url, self.cache_server) if self.cache_server else url
        pkg["download_dest"] = dest_base.joinpath(pkg_path.removeprefix("/"))
        pkg["download_size"] = Size(filesize=self.get_headers(url).get("content-size", size_fallback))
        pkg["is_compressed"] = self.is_compressed(url)
        pkg["status_ok"] = self.is_status_ok(url)
        pkg["install_target"] = "/"

        if not pkg.get("is_mandatory"):
            pkg["is_mandatory"] = False

        pkg["is_installed"] = self.all_files_installed(pkg["file_check"]) and self.package_is_installed(
            pkg["package_id"], pkg.get("package_vers", "0.0.0")
        )
        pkg["install_size"] = Size(filesize=pkg["install_size"])

        return pkg

    def parse_package_url_from_name(self, name: str, base: str) -> str:
        """Parse the full package url from the package name value.
        Where a url contains 'lp10_ms3_content_2016/../lp10_ms3_content_2013', it is correctly parsed to the right
        directory structure.
        :param name: string representation of package name; for example: 'MAContent10_GarageBand6Legacy.pkg'
        :param base: string representation of package base url; for example:
                         'https://audiocontentdownload.apple.com/lp10_ms3_content_2016/'"""
        base = f"{base}/" if not base.endswith("/") else base  # Ensure 'urljoin' correctly joins url paths
        return urljoin(base, name)
