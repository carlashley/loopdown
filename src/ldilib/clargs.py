"""Arguments for command line use."""
import argparse
import sys
import tempfile

from pathlib import Path
from typing import Optional
from . import _version_string
from .utils import (
    is_root,
    validate_caching_server_url,
    CachingServerMissingSchemeException,
    CachingServerPortException,
    CachingServerSchemeException,
)


def arguments(args: Optional[list] = None) -> argparse.Namespace:
    """Construct the arguments for command line usage."""
    applications = ["all", "garageband", "logicpro", "mainstage"]
    app_examplesc_str = ", ".join(f"'{app}'" for app in applications)
    name = Path(sys.argv[0]).name
    cache_example_str = "http://example.org:51492"
    log_levels = ["info", "debug"]
    log_levels_str = ", ".join(f"'{lvl}'" for lvl in log_levels)

    sa = argparse.ArgumentParser(add_help=False)  # For "super args!"
    sa.add_argument(
        "--advanced-help",
        action="store_true",
        dest="show_all_help",
        required=False,
        help=(
            "show hidden arguments; note, not all of these arguments should be directly modified,"
            " use these at your own risk"
        ),
    )
    sa_args, _ = sa.parse_known_args(args)
    parser = argparse.ArgumentParser(parents=[sa])

    a = parser.add_argument
    app = parser.add_mutually_exclusive_group().add_argument
    dwn = parser.add_mutually_exclusive_group().add_argument
    crt = parser.add_mutually_exclusive_group().add_argument

    a(
        "-n",
        "--dry-run",
        action="store_true",
        dest="dry_run",
        required=False,
        help="perform a dry run; no action taken",
    )

    app(
        "-a",
        "--apps",
        nargs="+",
        dest="apps",
        metavar="[app]",
        choices=applications,
        required=False,
        help=(
            f"application/s to process package content from; valid values are {app_examplesc_str},"
            " selecting 'all' will process packages for any/all of the three apps if found on the target device;"
            " note that the -p/--plist argument cannot be used with this argument"
        ),
    )

    app(
        "-p",
        "--plist",
        nargs="+",
        dest="plists",
        metavar="[plist]",
        required=False,
        help=(
            "property list/s to process package content from in the absence of an installed application;"
            " note that the -a/--apps argument cannot be used with this argument, use '--discover-plists' to"
            " discover available property lists"
        ),
    )

    a(
        "-m",
        "--mandatory",
        action="store_true",
        dest="mandatory",
        required=False,
        help="select all mandatory packages for processing; this and/or the -o/--optional argument is required",
    )

    a(
        "-o",
        "--optional",
        action="store_true",
        dest="optional",
        required=False,
        help="select all optional packages for processing; this and/or the -m/--mandatory argument is required",
    )

    # These two options are mutually exclusive when downloading the content
    dwn(
        "--cache-server",
        dest="cache_server",
        metavar="[server]",
        required=False,
        help=(
            f"the url representing an Apple caching server instance; for example: '{cache_example_str}';"
            " note that the --pkg-server argument cannot be used with this argument"
        ),
    )

    dwn(
        "--pkg-server",
        dest="pkg_server",
        metavar="[server]",
        required=False,
        help=(
            "the url representing a local mirror of package content; for example: 'https://example.org/'"
            " (the mirror must have the same folder structure as the Apple package server;"
            " note that the --cache-server argument cannot be used with this argument"
        ),
    )

    # These three options are mutually exclusive when creating a local mirror of the content
    crt(
        "--create-mirror",
        dest="create_mirror",
        type=Path,
        metavar="[path]",
        required=False,
        help=(
            "create a local mirror of the content following the same directory structure as the Apple"
            " audio content download structure"
        ),
    )

    crt(
        "-i",
        "--install",
        action="store_true",
        dest="install",
        required=False,
        help=(
            "install the content on this device; note, this does not override the Apple package install check scripts,"
            " installs will still fail if the Apple install checks fail, for example, an unsupported OS version, or"
            " no supported application is installed"
        ),
    )

    a(
        "--force",
        action="store_true",
        dest="force",
        required=False,
        help=(
            "forcibly performs the selected options regardless of pre-existing installations/downloads, etc;"
            " this will not force downloads/installs where fetching the audio content fails for various reasons"
        ),
    )

    a(
        "-s",
        "--silent",
        action="store_true",
        dest="silent",
        required=False,
        help="suppresses all output",
    )

    a(
        "--log-level",
        dest="log_level",
        metavar="[level]",
        choices=log_levels,
        required=False,
        default="info",
        help=f"set the logging level; valid options are {log_levels_str}",
    )

    a(
        "--version",
        action="version",
        version=_version_string,
    )

    # -- Hidden arguments here... THESE SHOULD NOT BE USED! -- #
    # This is a hidden argument that defines the base url used for pulling property list files that are
    # not present locally
    base_path_def = "https://audiocontentdownload.apple.com/lp10_ms3_content_2016/"
    a(
        "--feed-base-url",
        dest="feed_base_url",
        default=base_path_def,
        metavar="[path]",
        required=False,
        help=(
            argparse.SUPPRESS
            if not sa_args.show_all_help
            else (
                "specify the default base url path to use when fetching remote property list files, this"
                " url absolutely should not be modified unless you know what you are doing; default is"
                f" {base_path_def!r}"
            )
        ),
    )

    # This is a hidden argument for property list file discovery
    dwn(
        "--discover-plists",
        action="store_true",
        dest="discover_plists",
        required=False,
        help=(
            argparse.SUPPRESS
            if not sa_args.show_all_help
            else (
                "discover property list files for GarageBand, Logic Pro X, and MainStage 3 that Apple"
                "has released content for"
            )
        ),
    )

    # This is a hidden argument for property list file discovery start/end range
    disc_plists_def = [0, 99]
    disc_plists_def_str = ", ".join(f"'{val}'" for val in disc_plists_def)
    a(
        "--discover-plists-range",
        nargs=2,
        dest="discover_plists_range",
        default=disc_plists_def,
        type=int,
        metavar=("[min]", "[max]"),
        required=False,
        help=(
            argparse.SUPPRESS
            if not sa_args.show_all_help
            else ("specify the start and end range for property list discovery; defaults to" f" {disc_plists_def_str}")
        ),
    )

    # This is a hidden argument that defines the default download destination for all package downloads
    # (except for downloaded property list files which are downloaded to a temporary working folder in the
    # '/private/var/folders' directory)
    packages_dld_def = Path("/tmp/loopdown")
    a(
        "--default-packages-download-dest",
        dest="default_packages_download_dest",
        default=packages_dld_def,
        type=Path,
        metavar="[path]",
        required=False,
        help=(
            argparse.SUPPRESS
            if not sa_args.show_all_help
            else (
                "specify the default working path where all audio content packages will be downloaded to,"
                " this path absolutely should not be modified unless you know what you are doing;"
                f" default is {str(packages_dld_def)!r}"
            )
        ),
    )

    # This is a hidden argument that defines the default download destination for all 'working' downloads
    # of property list files which are downloaded to a temporary working folder in the
    # '/private/var/folders' directory)
    working_path_def = Path(tempfile.gettempdir()).joinpath("loopdown")
    a(
        "--default-working-download-dest",
        dest="default_working_download_dest",
        default=working_path_def,
        type=Path,
        metavar="[path]",
        required=False,
        help=(
            argparse.SUPPRESS
            if not sa_args.show_all_help
            else (
                "specify the default working path where all temporarily fetched property list files will"
                "be downloaded to (this directory is cleaned up after successful exit), this path absolutely"
                f" should not be modified unless you know what you are doing; default is {str(working_path_def)!r}"
            )
        ),
    )

    # This is a hidden argument that defines the default maximum number of retry attempts for all
    # curl requests.
    retry_max_def = "5"
    a(
        "--max-retries",
        dest="max_retries",
        default=retry_max_def,
        metavar="[retries]",
        required=False,
        help=(
            argparse.SUPPRESS
            if not sa_args.show_all_help
            else (
                "specify a maximum number of retries for all curl subprocess calls; default is"
                f" {retry_max_def} attempts"
            )
        ),
    )

    # This is a hidden argument that defines the default maximum amount of time for all retry
    # attempts for all curl requests.
    retry_timeout_def = "60"
    a(
        "--max-retry-time-limit",
        dest="max_retry_time_limit",
        default=retry_timeout_def,
        metavar="[seconds]",
        required=False,
        help=(
            argparse.SUPPRESS
            if not sa_args.show_all_help
            else (
                "specify a maximum amount of time that before retries fail for all curl subprocess calls"
                f"; default is {retry_timeout_def} seconds"
            )
        ),
    )

    # This is a hidden argument that allows addiontal arguments to be passed to curl for all curl requests.
    a(
        "--additional-curl-args",
        nargs="+",
        dest="proxy_args",
        metavar="[arg]",
        required=False,
        help=(
            argparse.SUPPRESS
            if not sa_args.show_all_help
            else (
                "additional arguments to pass to all curl subprocess calls; do not use this unless"
                "you know what you are doing"
            )
        ),
    )

    if not len(sys.argv) > 1:
        parser.print_help(sys.stderr)
        sys.exit(1)

    if sa_args.show_all_help:
        parser.print_help(sys.stderr)
        sys.exit(1)
    else:
        args = parser.parse_args()

    # ANy one of these specific arguments are required, possibly in combination with other arguments
    reqd_args = [
        args.apps,
        args.plists,
        args.mandatory,
        args.optional,
        args.create_mirror,
        args.discover_plists,
    ]
    reqd_arg_strs = [
        "-a/--apps",
        "-p/--plist",
        "-m/--mandatory",
        "-o/--optional",
        "--create-mirror",
    ]

    # Ignore dry run when discovering property list files.
    if args.dry_run and args.discover_plists:
        args.dry_run = False

    if args.install and not is_root():
        parser.print_usage(sys.stderr)
        print(f"{name}: error: you must be root to use -i/--install", file=sys.stderr)
        sys.exit(1)

    if not any(reqd_args):
        parser.print_usage(sys.stderr)
        print(
            f"{name}: error: one of or several of the following arguments are required: {', '.join(reqd_arg_strs)}",
            file=sys.stderr,
        )
        sys.exit(1)

    if args.install and args.plists:
        parser.print_usage(sys.stderr)
        print(
            f"{name}: error: argument -i/--install not allowed with argument -p/--plist",
            file=sys.stderr,
        )
        sys.exit(1)

    if not args.discover_plists and not (args.apps or args.plists):
        parser.print_usage(sys.stderr)
        print(
            f"{name}: error: one of the following arguments is required: -a/--apps or -p/--plists",
            file=sys.stderr,
        )
        sys.exit(1)

    if not args.discover_plists and not args.install and not args.create_mirror:
        parser.print_usage(sys.stderr)
        print(
            f"{name}: error: one of the following arguments is required: -i/--install or --create-mirror",
            file=sys.stderr,
        )
        sys.exit(1)

    if not args.discover_plists and not (args.mandatory or args.optional):
        parser.print_usage(sys.stderr)
        print(
            f"{name}: error: one of or both the following arguments are required: -o/--optional, -m/--mandatory",
            file=sys.stderr,
        )
        sys.exit(1)

    if args.cache_server:
        try:
            validate_caching_server_url(args.cache_server)
        except CachingServerMissingSchemeException as ms:
            parser.print_usage(sys.stderr)
            print(
                f"{name}: error: --cache-server parameter is missing scheme http://",
                file=sys.stderr,
            )
            sys.exit(1)
        except CachingServerSchemeException as se:
            parser.print_usage(sys.stderr)
            print(
                f"{name}: error: --cache-server parameter only supports 'http' schemes",
                file=sys.stderr,
            )
            sys.exit(1)
        except CachingServerPortException as pe:
            parser.print_usage(sys.stderr)
            print(
                f"{name}: error: --cache-server parameter must include a port number, for example: {cache_example_str}",
                file=sys.stderr,
            )
            sys.exit(1)

    # Now set default values for certain argument parameters; specifically if a package server mirror URL is not
    # provided, or if a cache server _is_ provided.
    if not args.pkg_server or args.cache_server:
        args.pkg_server = args.feed_base_url  # set the default Apple package server

    # Make sure the package server ends in an expected directory path
    if not args.cache_server and args.pkg_server and not args.pkg_server.endswith("/lp10_ms3_content_2016/"):
        args.pkg_server = f"{args.pkg_server}/lp10_ms3_content_2016/"

    # Replace the list of apps if "all" is in the argument parameter with the apps to check for
    if args.apps and "all" in args.apps:
        args.apps = ["garageband", "logicpro", "mainstage"]

    if args.discover_plists_range and not args.discover_plists:
        parser.print_usage(sys.stderr)
        print(
            f"{name}: error: --discover-plists-range not allowed without argument: --discovery-plists",
            file=sys.stderr,
        )
        sys.exit(1)
    elif args.discover_plists_range and args.discover_plists:
        _min, _max = args.discover_plists_range

        if _min >= _max:
            parser.print_usage(sys.stderr)
            print(
                f"{name}: error: --discover-plists-range values must be in 'min' 'max' order;",
                file=sys.stderr,
            )
            sys.exit(1)

    return args
