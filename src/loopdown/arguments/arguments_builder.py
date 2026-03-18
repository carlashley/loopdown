"""Build arguments."""

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


    def add_shared_options_to_subparser(
    p: argparse.ArgumentParser, *, main: StrictArgumentParser, pkg_group_registered: list[bool]
) -> None:
    """Adds options shared by both 'deploy' and 'download' subparsers.
    'main' is the top level StrictArgumentParser class; the package selection group is registered on it exactly once
    (controlled by 'pkg_group_registered') so that '_validate_any_required_groups' only runs a single check regardless
    of how many subparsers share those options.
    :param p: argparse.ArgumentParser object
    :param main: the top level StrictArgumentParser object
    :param pkg_group_registered: list of bools when 'any of required' type arguments are registered"""
    pkg_grp = p.add_argument_group(
        "package selection",
        description="at least one of -r/--req or -o/--opt is required",
    )

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
        "-f",
        "--force",
        action="store_true",
        dest="force",
        required=False,
        help="force the specified action",
    )

    req_action = pkg_grp.add_argument(
        "-r",
        "--req",
        action="store_true",
        dest="required",
        help="include the required audio packages",
    )

    opt_action = pkg_grp.add_argument(
        "-o",
        "--opt",
        action="store_true",
        dest="optional",
        help="include the optional audio packages"
    )

    # register any-of-required constrain on the main parser _once_. validation runs there because argparse
    # dispatches subparser parsing internally, bypassing our overridden parse_args on the subparser instance
    if not pkg_group_registered[0]:
        main.add_any_required_group(
            "package selection",
            description="at least one of -r/--req or -o/--opt is required",
        )

        # directly assign the actions capture from the first subparser's add_argument calls above;
        # both subparsers share teh same dest names so either set works
        main._any_required_groups[-1].actions = [req_action, opt_action]
        pkg_group_registered[0] = True


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

    # sentinel used to ensure any-of-required group for -r/--req and -o/--opt is registered on the main parser
    # once, even though add_shared_options_to_subparser is called once per subparser
    pkg_group_registered: list[bool] = [False]

    deploy = subparsers.add_parser(
        "deploy",
        formatter_class=QuotedChoicesHelpFormatter,
        help="deploy audio content packages locally (requires elevated permission when not performing dry-run)",
        description="Deploy audio content packages locally (requires elevated permission when not performing dry-run)",
    )

    add_shared_options_to_subparser(deploy, main=p, pkg_group_registered=pkg_group_registered)

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

    add_shared_options_to_subparser(download, main=p, pkg_group_registered=pkg_group_registered)

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
