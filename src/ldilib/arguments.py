"""Arguments for the command line."""
import argparse
import sys
import tempfile

from os import geteuid
from pathlib import Path
from typing import Callable, Optional
from urllib.parse import urlparse
from . import LoopdownMeta


class ArgumentChoices:
    """Argument choice values."""

    APPS: list[str] = ["all", "garageband", "logicpro", "mainstage"]
    CACHING_SRV_TYPES: list[str] = ["system", "user"]
    LOG_LEVELS: list[str] = ["info", "debug"]


class ArgumentExampleStrings:
    """Argument example strings."""

    PKG_SERVER: str = "https://example.org/"
    CACHE_SERVER: str = "http://localhost:55005"


class ArgumentDefaults:
    """Argument defaults."""

    CACHING_SRV_TYPE: str = "system"
    CACHING_SRV_RANK: int = 1
    LOG_DIR: Path = Path("/Users/Shared/loopdown")
    LOG_LEVEL: str = "info"
    PKG_DEST: Path = Path("/tmp/loopdown")
    RETRIES: int = 5
    TIMEOUT: int = 60
    PLISTS_MIN_MAX: list[int] = [0, 99]
    TMP_WORKING_DIR: Path = Path(tempfile.gettempdir()).joinpath("loopdown")
    FEED_BASE_URL: str = "https://audiocontentdownload.apple.com/lp10_ms3_content_2016/"


class PrettyArgChoices(argparse.HelpFormatter):
    """Formatter class to pretty-fy the help output of argparse.
    Help messages are printed out like:
    > ./foo.py -h
    usage: foo.py [-h] [-H]

    this is a description message

    options:
    -h/--help             show this help message and exit
    -H/--advanced-help    show the advanced help message and exit
    --/--opts, [opt] [[opt] ...]
                          this is an argument with options

    this is an epilog"""

    def _format_action_invocation(self, action):
        if not action.option_strings:
            default = self._get_default_metavar_for_positional(action)
            (metavar,) = self._metavar_formatter(action, default)(1)

            return metavar
        else:
            parts = []

            if action.nargs is None or action.nargs == 0:
                parts.extend(action.option_strings)
            else:
                default = self._get_default_metavar_for_optional(action)
                args_string = self._format_args(action, default)

                for opt_str in action.option_strings[:-1]:
                    parts.append(f"{opt_str}")

                parts.append(f"{action.option_strings[-1]}, {args_string}")

            return ", ".join(parts)


def _determine_log_dir_type(fp: Path) -> Optional[str]:
    """Determine if the log directory exists, and best guess the type it is (symlink/file/directory).
    :param fp: path object to test"""
    if fp.resolve().exists():
        if fp.resolve().is_file():
            return "file"

        if fp.resolve().is_dir() and fp.resolve().is_symlink():
            return "symlink"
        elif fp.resolve().is_dir() and not fp.resolve().is_symlink():
            return "directory"


def _validate_args(args: argparse.Namespace) -> tuple[bool, Optional[str]]:
    """Validates the download/install/discover plists arguments and returns a tuple value of a boolean and string.
    The boolean indicates arguments are valid, the string is any error message to return.
    :param args: argument namespace"""
    if not any((args.download, args.install, args.discover_plists)):
        arg1 = "-d/--download, -i/--install, or --discover-plists"
        arg_err = f"one or more arguments is required: {arg1}"
        return (False, arg_err)

    if args.install and not args.dry_run and not geteuid() == 0:
        arg1 = "-i/--install"
        arg_err = f"argument {arg1}: you must be root to run this script"
        return (False, arg_err)

    if (args.download or args.install) and not (args.mandatory or args.optional):
        arg1 = f"{'-d/--download' if args.download else '-i/--install'}"
        arg2 = "-m/--mandatory or -o/--optional"
        arg_err = f"argument {arg1}: requires either {arg2}"
        return (False, arg_err)

    if (args.download or args.install) and not args.apps:
        arg1 = f"{'-d/--download' if args.download else '-i/--install'}"
        arg2 = "-a/--apps"
        arg_err = f"argument {arg1}: requires {arg2}"
        return (False, arg_err)

    if args.silent and args.discover_plists:
        arg1 = "-s/--silent"
        arg2 = "--discover-plists"
        arg_err = f"argument: {arg1} not allowed with argument {arg2}"
        return (False, arg_err)

    if args.install and args.plists:
        arg1 = "-i/--install"
        arg2 = "-p/--plists"
        arg_err = f"argument: {arg1} not allowed with argument {arg2}"
        return (False, arg_err)

    if args.cache_server:
        arg1 = "--cache-server"
        url = urlparse(args.cache_server)
        scheme = url.scheme

        try:
            port = url.port
        except ValueError:
            arg_err = f"argument: {arg1} invalid port value"
            return (False, arg_err)

        if not scheme:
            arg_err = f"argument: {arg1} missing HTTP scheme prefix 'http://'"
            return (False, arg_err)

        if scheme and not scheme == "http":
            arg_err = f"argument: {arg1} invalid HTTP scheme, 'http://' only"
            return (False, arg_err)

        if not port:
            arg_err = f"argument: {arg1} missing port"
            return (False, arg_err)

        if port not in range(1, 65536):
            arg_err = f"argument: {arg1} invalid port: {port}"
            return (False, arg_err)

    if args.default_caching_server_rank < 0:
        arg1 = "--default-caching-server-rank"
        arg_err = f"argument: {arg1} negative values not allowed"
        return (False, arg_err)

    if args.default_log_directory:
        dir_type = _determine_log_dir_type(args.default_log_directory)

        if dir_type and not dir_type == "directory":
            arg1 = "--default-log-directory"
            arg_err = f"argument: {arg1} invalid directory type ({dir_type}), must specify a directory"

    return (True, None)


def print_help(fn: Callable) -> Callable:
    """Decorator for printing help."""

    def wrapper() -> argparse.Namespace:
        parser = fn()
        args = parser.parse_args()

        if not len(sys.argv) > 1 or args.advanced_help:
            parser.print_help(sys.stderr)
            sys.exit()

        return fn()

    return wrapper


def arg_validation(fn: Callable) -> Callable:
    """Decorator used for validating the entire argument namespace and setting some necessary defaults."""

    def wrapper() -> argparse.Namespace:
        parser = fn()
        args = parser.parse_args()

        try:
            if not args.advanced_help:
                validated_args, err_msg = _validate_args(args)

                if not validated_args and err_msg:
                    parser.error(err_msg)
        except AttributeError:
            pass

        return args

    return wrapper


def set_required_default_arg_values(fn: Callable) -> Callable:
    """Decorator used for setting some necessary default values for arguments under some specific
    scenarios"""

    def wrapper() -> argparse.Namespace:
        args = fn()
        opts = ArgumentChoices()
        defs = ArgumentDefaults()

        if args.apps and "all" in args.apps or args.discover_plists and not args.apps:
            args.apps = opts.APPS[1:]

        if (args.download or args.install) and not args.pkg_server:
            args.pkg_server = defs.FEED_BASE_URL

        if args.install:
            args.download = defs.PKG_DEST

        return args

    return wrapper


@set_required_default_arg_values
@arg_validation
@print_help
def clapper() -> argparse.Namespace:
    """Constructs command line arguments."""
    meta = LoopdownMeta
    opts = ArgumentChoices()
    defs = ArgumentDefaults()
    xmpl = ArgumentExampleStrings()

    adv_parser = argparse.ArgumentParser(
        description=meta.DESC.value,
        epilog=meta.VERSION_STR.value,
        formatter_class=PrettyArgChoices,
        add_help=False,
    )

    adv_parser.add_argument(
        "-H",
        "--advanced-help",
        action="store_true",
        dest="advanced_help",
        help="show the advanced help message and exit",
        required=False,
    )

    adv_args, _ = adv_parser.parse_known_args()

    parser = argparse.ArgumentParser(
        description=meta.DESC.value,
        epilog=meta.VERSION_STR.value,
        parents=[adv_parser],
        formatter_class=PrettyArgChoices,
    )

    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        dest="dry_run",
        help="perform a dry run",
        required=False,
    )

    parser.add_argument(
        "-v",
        "--version",
        action="version",
        dest="version",
        help="show version information",
        version=meta.VERSION_STR.value,
    )

    action_group = parser.add_mutually_exclusive_group()
    action_group.add_argument(
        "-d",
        "--download",
        dest="download",
        type=Path,
        metavar="[path]",
        help="download audio content (mirrors the Apple audio content server paths) to the specified directory",
        required=False,
    )

    action_group.add_argument(
        "-i",
        "--install",
        action="store_true",
        dest="install",
        help="download and install audio content",
        required=False,
    )

    apps_plist_group = parser.add_mutually_exclusive_group()
    apps_plist_group.add_argument(
        "-a",
        "--apps",
        dest="apps",
        type=str,
        nargs="+",
        metavar="[app]",
        choices=opts.APPS,
        help="performs the indicated action for the selected application/s, options are: %(choices)s",
        required=False,
    )

    apps_plist_group.add_argument(
        "-p",
        "--plist",
        dest="plists",
        type=str,
        nargs="+",
        metavar="[plist]",
        help="performs the indicated action for the specified plist/s; use --discover-plists to list options",
        required=False,
    )

    parser.add_argument(
        "-m",
        "--mandatory",
        action="store_true",
        dest="mandatory",
        help="selects the mandatory audio content packages",
        required=False,
    )

    parser.add_argument(
        "-o",
        "--optional",
        action="store_true",
        dest="optional",
        help="selects the optional audio content packages",
        required=False,
    )

    parser.add_argument(
        "-s",
        "--silent",
        action="store_true",
        dest="silent",
        help="suppresses all output (stdout and stderr)",
        required=False,
    )

    action_group.add_argument(
        "--discover-plists",
        dest="discover_plists",
        action="store_true",
        help="discover the property lists hosted by Apple for GarageBand, Logic Pro X, and MainStage 3",
        required=False,
    )

    cache_group = parser.add_mutually_exclusive_group()
    cache_group.add_argument(
        "--cache-server",
        dest="cache_server",
        type=str,
        metavar="[url]",
        help=(
            "specify auto for auto discovery or specify URL and port of a caching server, "
            f"for example: {xmpl.CACHE_SERVER}"
        ),
        required=False,
    )

    cache_group.add_argument(
        "--pkg-server",
        dest="pkg_server",
        type=str,
        metavar="[url]",
        help=(
            f"local server of mirrored content, provide the base URL only, for example: {xmpl.PKG_SERVER}"
        ),
        required=False,
    )

    parser.add_argument(
        "-f",
        "--force",
        action="store_true",
        dest="force",
        help="forcibly perfoms the specified actions regardless of pre-existing install/download data",
        required=False,
    )

    parser.add_argument(
        "--log-level",
        dest="log_level",
        metavar="[level]",
        choices=opts.LOG_LEVELS,
        default=defs.LOG_LEVEL,
        help=(
            argparse.SUPPRESS
            if not adv_args.advanced_help
            else (
                "sets the logging level, options are: %(choices)s, default is %(default)s"
            )
        ),
        required=False,
    )

    parser.add_argument(
        "--default-caching-server-rank",
        dest="default_caching_server_rank",
        type=int,
        metavar="[rank]",
        default=defs.CACHING_SRV_RANK,
        help=(
            argparse.SUPPRESS
            if not adv_args.advanced_help
            else (
                "specify the default rank value when looking for a caching server, default is %(default)s"
            )
        ),
        required=False,
    )

    parser.add_argument(
        "--default-caching-server-type",
        dest="default_caching_server_type",
        metavar="[type]",
        choices=opts.CACHING_SRV_TYPES,
        default=defs.CACHING_SRV_TYPE,
        help=(
            argparse.SUPPRESS
            if not adv_args.advanced_help
            else (
                "specify the default type when looking for a caching server, options are: %(choices)s, "
                "default is %(default)s"
            )
        ),
        required=False,
    )

    parser.add_argument(
        "--default-packages-download-dest",
        dest="default_packages_download_dest",
        type=Path,
        metavar="[dir]",
        default=defs.PKG_DEST,
        help=(
            argparse.SUPPRESS
            if not adv_args.advanced_help
            else (
                "specify the default directory packages download to, default is %(default)s"
            )
        ),
        required=False,
    )

    parser.add_argument(
        "--default-working-dest",
        dest="default_working_dest",
        type=Path,
        metavar="[dir]",
        default=defs.TMP_WORKING_DIR,
        help=(
            argparse.SUPPRESS
            if not adv_args.advanced_help
            else ("specify the default working directory, this can change on each run")
        ),
        required=False,
    )

    parser.add_argument(
        "--discover-plists-range",
        dest="discover_plists_range",
        type=int,
        nargs=2,
        metavar=("[min]", "[max]"),
        default=defs.PLISTS_MIN_MAX,
        help=(
            argparse.SUPPRESS
            if not adv_args.advanced_help
            else (
                "specify the min and max int values for discovering property lists, default is "
                f"{' and '.join(str(_) for _ in defs.PLISTS_MIN_MAX)}"
            )
        ),
        required=False,
    )

    parser.add_argument(
        "--feed-base-url",
        dest="feed_base_url",
        default=defs.FEED_BASE_URL,
        help=(
            argparse.SUPPRESS
            if not adv_args.advanced_help
            else (
                "specify the base url for fetching property lists from Apple, default is %(default)s"
            )
        ),
        required=False,
    )

    parser.add_argument(
        "--default-log-directory",
        dest="default_log_directory",
        type=Path,
        metavar="[dir]",
        default=defs.LOG_DIR,
        help=(
            argparse.SUPPRESS
            if not adv_args.advanced_help
            else ("specify the default log directory, default is %(default)s")
        ),
        required=False,
    )

    parser.add_argument(
        "--max-retries",
        dest="max_retries",
        type=int,
        metavar="[retries]",
        default=defs.RETRIES,
        help=(
            argparse.SUPPRESS
            if not adv_args.advanced_help
            else (
                "specify the maximum number of download retries, default is %(default)s"
            )
        ),
        required=False,
    )

    parser.add_argument(
        "--max-timeout",
        dest="max_timeout",
        type=int,
        metavar="[timeout]",
        default=defs.TIMEOUT,
        help=(
            argparse.SUPPRESS
            if not adv_args.advanced_help
            else (
                "specify the maximum number of seconds before timeout, default is %(default)s"
            )
        ),
        required=False,
    )

    parser.add_argument(
        "--additional-curl-args",
        dest="proxy_args",
        nargs="+",
        metavar="[arg]",
        help=(
            argparse.SUPPRESS
            if not adv_args.advanced_help
            else (
                "provide additional arguments and parameters to curl, such as proxy settings, use with caution"
            )
        ),
        required=False,
    )

    return parser
