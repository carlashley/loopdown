import argparse

from pathlib import Path

from .arg_formatters import QuotedChoicesHelpFormatter

# from .arg_helpers import AutoChoices, CachingServer, MirrorServer
from .arg_helpers import CachingServer, MirrorServer
from .arg_parser import StrictArgumentParser
from .arg_sentinels import AUTO, MISSING
from ..consts.apple_enums import ApplicationConsts
from ..consts.config_consts import ConfigurationConsts
from ..consts.version_enums import VersionInfo


def add_shared_options_to_subparser(p: argparse.ArgumentParser) -> None:
    """Adds options shared by both 'deploy' and 'download' subparsers."""
    p.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        dest="dry_run",
        required=False,
        help="perform a dry run; no mutating action taken",
    )

    p.add_argument(
        "-a",
        "--apps",
        choices=ApplicationConsts.SHORT_NAMES,
        default=ApplicationConsts.SHORT_NAMES,
        dest="applications",
        metavar="app",
        nargs="*",
        help=(
            "override the default %(default)s set of apps that audio content will be processed for;\nchoices are "
            "%(choices)s"
        ),
    )

    p.add_argument(
        "-r",
        "--req",
        action="store_true",
        dest="required",
        help="include the required audio packages",
    )

    p.add_argument(
        "-o",
        "--opt",
        action="store_true",
        dest="optional",
        help="include the optional audio packages"
    )

    p.add_argument(
        "-f",
        "--force",
        action="store_true",
        dest="force",
        required=False,
        help="force the specified action",
    )


def build_arguments() -> argparse.Namespace:
    """Build arguments for command line use."""
    p = StrictArgumentParser(
        prog="loopdown",
        description=(
            "Process additional content for installed audio applications, GarageBand, Logic Pro, and/or MainStage.\n"
        ),
        epilog=f"{VersionInfo.VERSION_STRING} {VersionInfo.LICENSE_STRING}",
        formatter_class=QuotedChoicesHelpFormatter,
    )

    p.add_argument(
        "-v",
        "--version",
        action="version",
        dest="version",
        version=VersionInfo.VERSION_STRING,
    )

    p.add_argument(
        "-l",
        "--log-level",
        choices=["critical", "error", "warning", "info", "debug", "notset"],
        default="info",
        dest="log_level",
        metavar="[level]",
        required=False,
        help="override the log level; default is %(default)s, choices are %(choices)s",
    )

    p.add_argument(
        "-q", "--quiet",
        action="store_true",
        dest="quiet",
        help="all console output (stdout/stderr) is suppressed; events logged to file only",
        required=False,
    )

    p.add_argument(
        "--log-file",
        default=ConfigurationConsts.DEFAULT_LOG_DIRECTORY.joinpath(ConfigurationConsts.DEFAULT_LOG_FILE),
        dest="log_file",
        metavar="[filepath]",
        required=False,
        type=Path,
        help=argparse.SUPPRESS,
    )

    p.add_argument(
        "--skip-pre-signature-check",
        action="store_true",
        dest="skip_pre_signature_check",
        required=False,
        help=(
            "skip the signature check of each downloaded package during pre-run analysis; speeds up processing"
            "for downloading (this is off by default in 'deploy' mode)"
        ),
    )

    # subcommands
    subparsers = p.add_subparsers(
        dest="action",
        metavar="[deploy,download]",
        required=True,
        help="use %(metavar)s -h for further help",
    )

    deploy = subparsers.add_parser(
        "deploy",
        formatter_class=QuotedChoicesHelpFormatter,
        help="deploy audio content packages locally (requires elevated permission when not performing dry-run)",
        description="Deploy audio content packages locally (requires elevated permission when not performing dry-run)",
    )

    add_shared_options_to_subparser(deploy)

    deploy.add_argument(
        "-c",
        "--cache-server",
        action=CachingServer,
        const=AUTO,
        dest="cache_server",
        metavar="url",
        nargs="?",
        required=False,
        help=(
            "use a caching server; when no server is specified, attempts to auto detect; expected format is "
            "'http://ipaddr:port'"
        ),
    )

    deploy.add_argument(
        "-m",
        "--mirror-server",
        action=MirrorServer,
        const=MISSING,  # flag missing when not provided so only check for argument value when provided
        dest="mirror_server",
        metavar="[url]",
        nargs="?",
        required=False,
        help="local mirror server to use; expected format is 'https://example.org'",
    )

    download = subparsers.add_parser(
        "download",
        formatter_class=QuotedChoicesHelpFormatter,
        help="download audio content packages locally",
        description="Download audio content packages locally"
    )

    add_shared_options_to_subparser(download)

    download.add_argument(
        "-d",
        "--dest",
        default=ConfigurationConsts.DEFAULT_DOWNLOAD_DEST,
        dest="destination",
        metavar="[dir]",
        required=False,
        type=Path,
        help="override the download directory path when '--download-only' used; default is %(default)s",
    )

    return p.parse_args()
