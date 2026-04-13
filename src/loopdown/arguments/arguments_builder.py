"""Build arguments."""

import argparse

from pathlib import Path

from .arg_formatters import QuotedChoicesHelpFormatter

from .arg_helpers import AUTO, CachingServer, MirrorServer, MISSING
from .arg_parser import StrictArgumentParser
from .._config import ApplicationConsts, ConfigurationConsts, VersionInfo

type PackageActions = tuple[argparse.Action, argparse.Action, argparse.Action]


def add_shared_options_to_subparser(p: argparse.ArgumentParser) -> PackageActions:
    """Adds options shared by both 'deploy' and 'download' subparsers. Returns the 'required' and 'optional'
    argument actions in a tuple for later attachment to the main parser to ensure validating the actions occurs."""
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

    esn_arg = pkg_grp.add_argument(
        "-e",
        "--esn",
        action="store_true",
        dest="essential",
        help="include the essential audio packages (Logic Pro 12+ and MainStage 4+ only)",
    )

    core_arg = pkg_grp.add_argument(
        "-r",
        "--core",
        action="store_true",
        dest="core",
        help="include the core audio packages (equivalent to '-r/--req' for legacy audio applications)",
    )

    opt_arg = pkg_grp.add_argument(
        "-o", "--opt", action="store_true", dest="optional", help="include the optional audio packages"
    )

    return (esn_arg, core_arg, opt_arg)


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
        "-q",
        "--quiet",
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
        "--no-proxy",
        action="store_true",
        dest="no_proxy",
        help="ignore proxies for '*' in all curl subprocess calls",
        required=False,
    )

    p.add_argument(
        "--skip-signature-check",
        action="store_true",
        dest="skip_sig_check",
        required=False,
        help="skip the signature check after downloads (this is off by default in 'deploy' mode and in dry-runs)",
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

    deploy.add_argument(
        "-b",
        "--library-dest",
        type=Path,
        dest="library_path",
        metavar="[dir]",
        default=Path("/Users/Shared/Logic Pro Library.bundle"),
        help=(
            "the destination where modern Logic Pro 12+ and MainStage 4+ content is deployed to; "
            "default is %(default)s"
        ),
        required=False,
    )

    # add shared options, get required and optional arg actions
    esn_arg, core_arg, opt_arg = add_shared_options_to_subparser(deploy)

    # always use default download dest in deployment mode
    deploy.set_defaults(destination=ConfigurationConsts.DEFAULT_DOWNLOAD_DEST)

    cache_arg = deploy.add_argument(
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

    mirror_arg = deploy.add_argument(
        "-m",
        "--mirror-server",
        action=MirrorServer,
        const=MISSING,  # store MISSING when flag given without a value to help with exclusive checks
        dest="mirror_server",
        metavar="url",
        nargs="?",
        required=False,
        help="local mirror server to use; expected format is 'https://example.org'",
    )

    download = subparsers.add_parser(
        "download",
        formatter_class=QuotedChoicesHelpFormatter,
        help="download audio content packages locally",
        description="Download audio content packages locally",
    )

    # discard the req/opt arg actions here; not used in download mode
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

    # main parser group registrations
    # register constrains on the main parser; argparse dispatches subparser parsing internally,
    # bypassing our overridden parse_args on the subparser instances, so validation of args must live
    # here

    # registering at least one of -e/--esn, -r/--core or -o/--opt is required
    p.add_any_required_group(
        "package selection",
        description="at least one of -e/--esn, -r/--core, or -o/--opt is required",
    )
    p.any_required_groups[-1].actions = [esn_arg, core_arg, opt_arg]

    # registering cache/mirror args to the main parser to ensure validation of exclusivity occurs
    p.add_exclusive_group(
        "server selection",
        message="-c/--cache-server and -m/--mirror-server are mutually exclusive",
    )
    p.all_exclusive_groups[-1].actions = [cache_arg, mirror_arg]

    return p.parse_args()
