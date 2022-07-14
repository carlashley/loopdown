#!/usr/bin/env python3
"""Download or print out the URL to the additional content packages that Apple
provides for the GarageBand, Logic Pro, and MainStage audio programs.

usage: loopdown.py [-h] [-n] [-m] [-o] [-d [path]] -p [[file] ...]
                   [--retries [retry]] [-v]

options:
  -h, --help            show this help message and exit
  -n, --dry-run         performs a dry run (prints each URL to screen)
  -m, --mandatory       process mandatory packages, either this or
                        -o/--optional is required
  -o, --optional        process optional packages, either this or
                        -m/--mandatory is required
  -d [path], --destination [path]
                        path to download destination, folder path will be
                        created automatically if it does not exist; defaults
                        to '/tmp/loopdown' for non dry-runs
  -p [[file] ...], --property-list [[file] ...]
                        path to property list file/s to process, must be valid
                        file path and property list file; required
  --retries [retry]     maximum number of retries (default 3)
  -v, --version         show program's version number and exit

loopdown v1.0.1 is provided 'as is'; licensed under the Apache License 2.0
"""
import argparse
import errno
import plistlib
import subprocess
import sys

from pathlib import Path
from urllib.parse import urlparse
from typing import Any, Dict, List, Optional

APPLE_BASE_URL = "https://audiocontentdownload.apple.com"
APPLE_FEED_URL = "https://audiocontentdownload.apple.com/lp10_ms3_content_2016"
SUFFIXES = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
VERSION = "1.0.2"
USERAGENT = f"loopdown/{VERSION}"
DEFAULT_DEST = "/tmp/loopdown"


def arguments() -> argparse.Namespace:
    """Create the command line arguments."""
    p = argparse.ArgumentParser()
    aa = p.add_argument
    me = p.add_mutually_exclusive_group().add_argument
    name = Path(sys.argv[0]).name

    aa("-n", "--dry-run",
       action="store_true",
       dest="dry_run",
       help="performs a dry run (prints each URL to screen)",
       required=False)

    aa("-m", "--mandatory",
       action="store_true",
       dest="mandatory",
       help=("process mandatory packages, either this or"
             " -o/--optional is required"),
       required=False)

    aa("-o", "--optional",
       action="store_true",
       dest="optional",
       help=("process optional packages, either this or"
             " -m/--mandatory is required"),
       required=False)

    aa("-d", "--destination",
       dest="destination",
       default=DEFAULT_DEST,
       metavar="[path]",
       help=("path to download destination, folder path will be created"
             " automatically if it does not exist; defaults to"
             f" {DEFAULT_DEST!r} for non dry-runs"),
       required=False)

    me("-p", "--property-list",
       nargs="*",
       dest="plists",
       metavar="[file]",
       help=("path to property list file/s to process, must be valid file path"
             " and property list file; required"),
       required=False)

    me("-t", "--text-file",
       dest="text_file",
       metavar="[file]",
       help="download audio content packages from URLs in a text file",
       required=False)

    aa("--retries",
       dest="retries",
       default="3",
       metavar="[retry]",
       help="maximum number of retries (default 3)",
       required=False)

    aa("-v", "--version",
       action="version",
       version=(f"loopdown v{VERSION} is provided 'as is';"
                " licensed under the Apache License 2.0"))

    args = p.parse_args()
    args.destination = Path(args.destination)
    args.text_file = Path(args.text_file) if args.text_file else None
    args.plists = [Path(fp) for fp in args.plists] if args.plists else None

    if args.plists:
        files = list()

        for fp in args.plists:
            if fp.is_file():
                files.append(Path(fp))
            elif fp.is_dir():
                files.extend([fn for fn in fp.rglob("*.plist")])

        args.plists = files

    if not args.dry_run and not args.destination:
        p.print_usage()
        print((f"{name}: error: the following arguments are required:"
               " -d/--destination"), file=sys.stderr)
        sys.exit(1)

    if not (args.plists or args.text_file):
        p.print_usage()
        print((f"{name}: error: at least one of the following arguments is"
               " required: -t/--text-file, -p/--property-list"), file=sys.stderr)
        sys.exit(1)

    if not (args.mandatory or args.optional):
        p.print_usage()
        print((f"{name}: error: at least one of the following arguments is"
               " required: -m/--mandatory, -o/--optional"), file=sys.stderr)
        sys.exit(1)

    return args


def bytes2hr(b: str, counter: int = 0, byteblock: int = 1024) -> Optional[str]:
    """Convert bytes to human readable value
    :param b: bytes as string value"""
    b = int(b)

    while b > byteblock and counter < len(SUFFIXES):
        counter += 1
        b /= float(byteblock)

    suffix = SUFFIXES[counter]
    return f"{b:.2f}{suffix}"


def download(url: str, dest: Path, retries: str = "3") -> None:
    """Download the URL to the supplied destination.
    :param url: URL to download
    :param dest: destination folder path to download the file to
    :param retries: number of retries to attempt if download fails"""
    dest = dest.joinpath(urlparse(url).path.lstrip("/"))
    cmd = ["/usr/bin/curl", "-L", "-C", "-", "--retry", retries,
           "--user-agent", USERAGENT, "--progress-bar", "--create-dirs", url,
           "-o", str(dest)]

    subprocess.run(cmd)


def download_size(url: str) -> Optional[str]:
    """Get the content-length header"""
    cmd = ["/usr/bin/curl", "-s", "-I", url]
    cl = "Content-Length: "
    p = subprocess.run(cmd, capture_output=True, encoding="utf-8")

    if p.returncode == 0:
        splitlines = p.stdout.strip().splitlines()
        size = "".join([line.replace(cl, "") for line in splitlines
                        if cl in line])
        return bytes2hr(size)


def pull_urls(data: Dict[Any, Any], mandatory: bool = False,
              optional: bool = False) -> Optional[List[str]]:
    """Pulls URL's of packages to download from the supplied data source.
    :param data: dictionary of loop objects to process
    :param mandatory: process mandatory packages
    :param optional: process optional packages"""
    result = set()

    for k, v in data["Packages"].items():
        dn = v["DownloadName"]

        if "lp10_ms3_content_2013" in dn:
            url = f"{APPLE_BASE_URL}/{dn.replace('../', '')}"
        else:
            url = f"{APPLE_FEED_URL}/{dn}"

        mnd = v.get("IsMandatory", False)

        if mnd and mandatory:
            result.add(url)
        elif not mnd and optional:
            result.add(url)

    result = sorted(list(result))
    return result


def readplist(fp: Path) -> Optional[Dict[Any, Any]]:
    """Read the specified property list file.
    :param fp: path to the property list file to read."""
    try:
        with fp.open("rb") as f:
            data = plistlib.load(f)

            if not data.get("Packages"):
                print((f"Error: Could not find package content in {str(fp)!r}."
                      " This file may not be a valid audio content property list."))
                sys.exit(1)

            return data
    except FileNotFoundError as e:
        print(f"Error: {e.strerror}: {str(fp)!r}", file=sys.stderr)
        sys.exit(errno.ENOENT)


def readfile(fp: Path, ext: str = ".pkg") -> Optional[List[str]]:
    """Read a text file for URL's"""
    try:
        with fp.open("r") as f:
            return {line.strip() for line in f.readlines()
                    if APPLE_BASE_URL in line and line.strip().endswith(ext)}
    except FileNotFoundError as e:
        print(f"Error: {e.strerror}: {str(fp)!r}", file=sys.stderr)
        sys.exit(errno.ENOENT)


def main():
    args = arguments()
    package_urls = set()
    counter = 1

    if args.plists:
        for plist in args.plists:
            data = readplist(plist)
            urls = pull_urls(data, args.mandatory, args.optional)

            for url in urls:
                package_urls.add(url)
    elif args.text_file:
        package_urls = readfile(args.text_file)

    package_urls = sorted(list(package_urls))
    count = len(package_urls)

    for url in package_urls:
        if not args.dry_run:
            size = download_size(url)
            dn = Path(urlparse(url).path).name
            print(f"Downloading {dn} ({size}, {counter} of {count}):")
            download(url=url, dest=args.destination, retries=args.retries)
            counter += 1
        else:
            print(url)

    if not args.dry_run:
        print(f"Loop content downloaded to {str(args.destination)!r}")


if __name__ == "__main__":
    main()
