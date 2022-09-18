#!/usr/bin/env python3
"""Download or print out the URL to the additional content packages that Apple
provides for the GarageBand, Logic Pro, and MainStage audio programs.

usage: loopdown.py [-h] [-n] [-m] [-o] [-d [path]] [-p [[file] ...] | -t [file]] [--retries [retry]] [-v]

loopdown v1.0.20220918 is a utility to download the audio content packages
from Apple so they can be deployed with third party app management tools
such as 'munki' or 'JAMF'.

Basic usage example:
  loopdown -p garageband1021.plist -m -d ~/Desktop/appleaudiocontent

If a specified property list file is not found at the specified path, then
loopdown will fallback to a remote version of that property list file, if
available.

The specific property list files are usually found in the app bundle:
  /Applications/[app]/Contents/Resources/[appname]NNNN.plist
'NNNN' represents a 'version' number.

For example:

  /Applications/GarageBand.app/Contents/Resources/garageband1021.plist

Note: The property list file does not always get updated with each audio app
release.

For the most recent version of loopdown:
  git: https://github.com/carlashley/loopdown

options:
  -h, --help            show this help message and exit
  -n, --dry-run         performs a dry run (prints each URL to screen)
  -m, --mandatory       process mandatory packages, either this or -o/--optional is required
  -o, --optional        process optional packages, either this or -m/--mandatory is required
  -d [path], --destination [path]
                        path to download destination, folder path will be created
                        automatically if it does not exist; defaults to '/tmp/loopdown'
                        for non dry-runs
  -p [[file] ...], --property-list [[file] ...]
                        path to property list file/s to process, must be valid file path
                        and property list file; required
  -t [file], --text-file [file]
                        download audio content packages from URLs in a text file
  --retries [retry]     maximum number of retries (default 3)
  -v, --version         show program's version number and exit

loopdown is provided 'as is'; licensed under the Apache License 2.0
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
VERSION = "1.0.20220918"
USERAGENT = f"loopdown/{VERSION}"
DEFAULT_DEST = "/tmp/loopdown"
ARGPARSE_DESC = (f"loopdown v{VERSION} is a utility to download the audio content packages\n"
                 "from Apple so they can be deployed with third party app management tools\n"
                 "such as 'munki' or 'JAMF'.\n \n"
                 "Basic usage example:\n"
                 "  loopdown -p garageband1021.plist -m -d ~/Desktop/appleaudiocontent\n \n"
                 "If a specified property list file is not found at the specified path, then\n"
                 "loopdown will fallback to a remote version of that property list file, if\n"
                 "available.\n \n"
                 "The specific property list files are usually found in the app bundle:\n"
                 "  /Applications/[app]/Contents/Resources/[appname]NNNN.plist\n"
                 "'NNNN' represents a 'version' number.\n \n"
                 "For example:\n \n"
                 "  /Applications/GarageBand.app/Contents/Resources/garageband1021.plist\n \n"
                 "Note: The property list file does not always get updated with each audio app\n"
                 "release.\n \n"
                 "For the most recent version of loopdown:\n"
                 "  git: https://github.com/carlashley/loopdown")


def arguments() -> argparse.Namespace:
    """Create the command line arguments."""
    p = argparse.ArgumentParser(description=ARGPARSE_DESC, formatter_class=argparse.RawTextHelpFormatter)
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
             "\nautomatically if it does not exist; defaults to"
             f" {DEFAULT_DEST!r}\nfor non dry-runs"),
       required=False)

    me("-p", "--property-list",
       nargs="*",
       dest="plists",
       metavar="[file]",
       help=("path to property list file/s to process, must be valid file path"
             "\nand property list file; required"),
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
            else:
                files.append(Path(fp))  # Allow for fallback

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
    """Convert bytes to human readable value.

    :param b: bytes as string value
    :param counter: count from position index
    :param byteblock: bytes per KB"""
    b = int(b)

    while b > byteblock and counter < len(SUFFIXES):
        counter += 1
        b /= float(byteblock)

    suffix = SUFFIXES[counter]
    return f"{b:.2f}{suffix}"


def download(url: str, dest: Path, retries: str = "3", compressed: bool = False) -> None:
    """Download the URL to the supplied destination.

    :param url: URL to download
    :param dest: destination folder path to download the file to
    :param retries: number of retries to attempt if download fails
    :param compressed: indicates if the remote resource is compressed"""
    dest = dest if dest.suffix == ".plist" else dest.joinpath(urlparse(url).path.lstrip("/"))
    cmd = ["/usr/bin/curl", "-L", "-C", "-", "--retry", retries,
           "--user-agent", USERAGENT, "--progress-bar", "--create-dirs", url,
           "-o", str(dest)]

    if compressed:
        cmd.append("--compressed")

    if dest.suffix == ".plist":
        cmd.append("--silent")

    subprocess.run(cmd)


def get_header(url: str, header: str) -> Optional[str]:
    """Get header and its value.

    :param url: url
    :param header: header to return value of"""
    cmd = ["/usr/bin/curl", "-s", "-I", url]
    p = subprocess.run(cmd, capture_output=True, encoding="utf-8")

    if p.returncode == 0:
        return "".join([ln.replace(header, "") for ln in p.stdout.strip().splitlines()
                        if header.lower() in ln.lower()])


def download_size(url: str, header: str) -> Optional[str]:
    """Get the content-length header.

    :param url: url to calculate size of"""
    size = get_header(url=url, header="content-length")
    return bytes2hr(size) if size else None


def status_code(url: str) -> Optional[int]:
    """HTTP status code of remote resource.

    :param urul: url"""
    cmd = ["/usr/bin/curl", "-s", "-o", "/dev/null", "-I", "-w", "%{http_code}", "https://example.org"]
    p = subprocess.run(cmd, capture_output=True, encoding="utf-8")

    if p.returncode == 0:
        return int(p.stdout.strip())
    else:
        raise Exception(f"Error: {' '.join(cmd)} exit code: {p.returncode}")


def encoding_type(url: str) -> bool:
    """Return encoding type (for exmaple 'gzip') if the remote resource has the 'content-encoding' header.

    :param url: url of remote resource"""
    return get_header(url=url, header="content-encoding")


def pull_urls(data: Dict[Any, Any],
              mandatory: bool = False,
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


def readfile(fp: Path,
             ext: str = ".pkg") -> Optional[List[str]]:
    """Read a text file for URL's.

    :param fp: path to text file
    :param ext: package file extension"""
    try:
        with fp.open("r") as f:
            return {line.strip() for line in f.readlines()
                    if APPLE_BASE_URL in line and line.strip().endswith(ext)}
    except FileNotFoundError as e:
        print(f"Error: {e.strerror}: {str(fp)!r}", file=sys.stderr)
        sys.exit(errno.ENOENT)


def fallback(fp: Path) -> Optional[Dict[Any, Any]]:
    """Perform fallback download.

    :param fp: plist file path"""
    url = f"{APPLE_FEED_URL}/{fp.name}"
    sc = status_code(url)
    print(f"Falling back to {url!r}")

    if sc == 200:
        tmp_dest = Path(f"/tmp/{fp.name}")
        compressed = encoding_type(url) == "gzip"
        download(url=url, dest=tmp_dest, compressed=compressed)

        if tmp_dest.exists():
            try:
                data = readplist(tmp_dest)
                tmp_dest.unlink(missing_ok=True)
                return data
            except plistlib.InvalidFileException:
                print(f"Error: {url!r} is not a valid XML file, skipping.")
                tmp_dest.unlink(missing_ok=True)


def main():
    """Main"""
    args = arguments()
    package_urls = set()
    counter = 1

    if args.plists:
        for plist in args.plists:
            if not plist.exists():
                data = fallback(plist)
            else:
                data = readplist(plist)

            # Only carry on if 'data' exists.
            if data:
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
