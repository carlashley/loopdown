"""Arguments for command line use."""
import argparse
import sys
import tempfile

from pathlib import Path
from . import __version_string__

from .utils import (
    is_root,
    validate_caching_server_url,
    CachingServerMissingSchemeException,
    CachingServerPortException,
    CachingServerSchemeException,
)


def arguments() -> argparse.Namespace:
    """Construct the arguments for command line usage."""
    applications = ["all", "garageband", "logicpro", "mainstage"]
    app_examplesc_str = ", ".join(f"'{app}'" for app in applications)
    name = Path(sys.argv[0]).name
    cache_example_str = "http://example.org:51492"
    log_levels = ["info", "debug"]
    log_levels_str = ", ".join(f"'{lvl}'" for lvl in log_levels)

    parser = argparse.ArgumentParser()
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
        metavar="[path|url]",
        required=False,
        help=(
            "property list/s to process package content from in the absence of an installed application;"
            " note that the -a/--apps argument cannot be used with this argument"
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
        help="forcibly performs the selected options regardless of pre-existing installations/downloads, etc",
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
        version=__version_string__,
    )

    # -- Hidden arguments here... THESE SHOULD NOT BE USED! -- #
    # This is a hidden argument that defines the base url used for pulling property list files that are
    # not present locally
    a(
        "--feed-base-url",
        dest="feed_base_url",
        default="https://audiocontentdownload.apple.com/lp10_ms3_content_2016/",
        required=False,
        help=argparse.SUPPRESS,
    )

    # This is a hidden argument that defines the default download destination for all package downloads
    # (except for downloaded property list files which are downloaded to a temporary working folder in the
    # '/private/var/folders' directory)
    a(
        "--default-packages-download-dest",
        dest="default_packages_download_dest",
        default=Path("/tmp/loopdown"),
        required=False,
        help=argparse.SUPPRESS,
    )

    # This is a hidden argument that defines the default download destination for all 'working' downloads
    # of property list files which are downloaded to a temporary working folder in the
    # '/private/var/folders' directory)
    a(
        "--default-working-download-dest",
        dest="default_working_download_dest",
        default=Path(tempfile.gettempdir()).joinpath("loopdown"),
        required=False,
        help=argparse.SUPPRESS,
    )

    if not len(sys.argv) > 1:
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args()

    # ANy one of these specific arguments are required, possibly in combination with other arguments
    reqd_args = [
        args.apps,
        args.plists,
        args.mandatory,
        args.optional,
        args.create_mirror,
    ]
    reqd_arg_strs = [
        "-a/--apps",
        "-p/--plist",
        "-m/--mandatory",
        "-o/--optional",
        "--create-mirror",
    ]

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

    if not (args.apps or args.plists):
        parser.print_usage(sys.stderr)
        print(
            f"{name}: error: one of the following arguments is required: -a/--apps or -p/--plists",
            file=sys.stderr,
        )
        sys.exit(1)

    if not args.install and not args.create_mirror:
        parser.print_usage(sys.stderr)
        print(
            f"{name}: error: one of the following arguments is required: -i/--installor or --create-mirror",
            file=sys.stderr,
        )
        sys.exit(1)

    if not (args.mandatory or args.optional):
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

    # Now set default values for certain argument parameters
    if not (args.pkg_server and args.cache_server):
        args.pkg_server = args.feed_base_url  # set the default Apple package server

    # Make sure the package server ends in an expected directory path
    if not args.cache_server and args.pkg_server and not args.pkg_server.endswith("/lp10_ms3_content_2016/"):
        args.pkg_server = f"{args.pkg_server}/lp10_ms3_content_2016/"

    # Replace the list of apps if "all" is in the argument parameter with the apps to check for
    if args.apps and "all" in args.apps:
        args.apps = ["garageband", "logicpro", "mainstage"]

    return args
