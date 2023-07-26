"""Arguments for command line use."""
import argparse

from urllib.parse import urlparse

from .arguments import arg_config
from .arguments.constructor import construct_arguments
from .utils import (
    is_root,
    locate_caching_server,
    validate_caching_server_url,
    CachingServerAutoLocateException,
    CachingServerMissingSchemeException,
    CachingServerPortException,
    CachingServerSchemeException,
)


def arguments() -> argparse.Namespace:
    """Public function for arguments, includes additional checks that argparse cannot do, such as
    mutually exclusive arguments that are cross exclusive."""

    def join_args(a: list[str], sep: str = ", ", suffix: str = "or") -> str:
        """Joins a group of argument strings into a single string.
        :param a: list of argument string values; for example ['-a/--apple', '--bannana']
        :param sep: seperator string; default is ','
        :param suffix: the suffix string that 'joins' a list of more than 1 argument; default is 'or'"""
        if len(a) >= 2:
            return f"{sep}".join(a[0:-1]) + f" {suffix} {a[-1]}"
        else:
            return f"{sep}".join(a)

    args, parser, opts_map = construct_arguments(arg_config)

    # Convert specific args to correct types.
    args.max_retries = str(args.max_retries)
    args.max_retry_time_limit = str(args.max_retry_time_limit)

    # -a/--apps must be corrected here to ensure the right list of values is passed on
    if (args.apps and "all" in args.apps) or (args.discover_plists and not args.apps):
        args.apps = ["garageband", "logicpro", "mainstage"]

    # A minimum of -a/--apps, --create-mirror, --discover-plists, or --plists is required
    if not any([args.apps, args.create_mirror, args.discover_plists, args.plists]):
        argstr = join_args([opts_map[arg] for arg in ["apps", "create_mirror", "discover_plists", "plists"]])
        parser.error(f"one or more of these arguments is required: {argstr}")

    # -i/--install and --create-mirror require either -m/--mandatory and/or -o/--optional
    if (args.install or args.create_mirror) and not any([args.mandatory, args.optional]):
        prefix = opts_map["install" if args.install else "create_mirror"]
        argstr = join_args([opts_map[arg] for arg in ["mandatory", "optional"]], suffix="and/or")
        parser.error(f"argument {prefix}: not allowed without: {argstr}")

    # -i/--install is not allowed with --create-mirror or -p/--plists
    if args.install and any([args.create_mirror, args.plists]):
        prefix = opts_map["install"]
        argstr = join_args([opts_map[arg] for arg in ["create_mirror", "plists"]])
        parser.error(f"argument {prefix}: not allowed with {argstr}")

    # -a/--apps is not allowed without --create-mirror, --discover-plists, or -i/--install
    if args.apps and not any([args.create_mirror, args.discover_plists, args.install]):
        prefix = opts_map["apps"]
        argstr = join_args([opts_map[arg] for arg in ["create_mirror", "discover_plists", "install"]])
        parser.error(f"argument {prefix}: not allowed without: {argstr}")

    # -p/--plists not allowd without --create-mirror
    if args.plists and not args.create_mirror:
        prefix = opts_map["plists"]
        argstr = join_args([opts_map["create_mirror"]])
        parser.error(f"argument {prefix}: not allowed without: {argstr}")

    # --discover-plists not allowed with -a/--apps, --cache-server, --create-mirror, -n/--dry-run,
    # -f/--force, -i/--install, -m/--mandatory, -o/--optional, -p/--plists, --pkg-server, or -s/--silent
    if args.discover_plists and any(
        [
            args.cache_server,
            args.create_mirror,
            args.dry_run,
            args.force,
            args.install,
            args.mandatory,
            args.optional,
            args.plists,
            args.pkg_server,
            args.silent,
        ]
    ):
        if args.cache_server:
            prefix = opts_map["cache_server"]
        elif args.create_mirror:
            prefix = opts_map["create_mirror"]
        elif args.dry_run:
            prefix = opts_map["dry_run"]
        elif args.force:
            prefix = opts_map["force"]
        elif args.install:
            prefix = opts_map["install"]
        elif args.mandatory:
            prefix = opts_map["mandatory"]
        elif args.optional:
            prefix = opts_map["optional"]
        elif args.plists:
            prefix = opts_map["plists"]
        elif args.pkg_server:
            prefix = opts_map["pkg_server"]
        elif args.silent:
            prefix = opts_map["silent"]

        argstr = join_args([opts_map["discover_plists"]])
        parser.error(f"argument {prefix}: not allowed with {argstr}")

    # --discover-plists-range not allowed without --discover-plists
    if args.discover_plists_range and not args.discover_plists_range == [0, 99] and not args.discover_plists:
        prefix = opts_map["discover_plists_range"]
        argstr = join_args([opts_map["discover_plists"]])
        parser.error(f"argument {prefix}: not allowed without: {argstr}")

    # -f/--force not allowed without --create-mirror or -i/--install
    if args.force and not any([args.create_mirror, args.install]):
        prefix = opts_map["force"]
        argstr = join_args([opts_map[arg] for arg in ["create_mirror", "force"]])
        parser.error(f"argument {prefix}: not allowed without {argstr}")

    # --cache-server not allowed with --create-mirror
    if args.cache_server and args.create_mirror:
        prefix = opts_map["cache_server"]
        argstr = join_args([opts_map["create_mirror"]])
        parser.error(f"argument {prefix}: not allowed without {argstr}")

    # --pkg-server not allowed without -i/--install
    if args.pkg_server and not args.install:
        prefix = opts_map["pkg_server"]
        argstr = join_args([opts_map["install"]])
        parser.error(f"argument {prefix}: not allowed without {argstr}")

    # --install requires higher privileges
    if args.install and not is_root():
        prefix = opts_map["install"]
        parser.error(f"argument {prefix}: you must be root to use this argument")

    # --default-warning-threshold checks
    if args.default_warn_threshold and not args.discover_plists:
        min_v, max_v = 0.1, 1.0
        prefix = opts_map["default_warn_threshold"]

        # --default-warning-threshold not allowed without --create-mirror or -i/--install
        if not any([args.create_mirror, args.install]):
            argstr = join_args([opts_map[arg] for arg in ["create_mirror", "install"]])
            parser.error(f"argument {prefix}: not allowed without {argstr}")

        # --default-warning-threshold must be between acceptable min/max float value
        if not min_v <= args.default_warn_threshold <= max_v:
            parser.error(f"argument {prefix}: argument value must be between '{min_v}' and '{max_v}'")

    # --default-log-directory must exist and be a directory
    if args.default_log_directory:
        prefix = opts_map["default_log_directory"]
        log_dir_exists = args.default_log_directory.resolve().exists()
        log_dir_is_dir = args.default_log_directory.resolve().is_dir()
        log_dir_is_syl = args.default_log_directory.resolve().is_symlink()
        path_type = "symlink" if log_dir_is_syl else "file" if not log_dir_is_dir else "directory"

        if log_dir_exists and not log_dir_is_dir:
            parser.error(f"argument {prefix}: argument value must be a directory path, not a {path_type}")

    # Make sure args.pkg_server points to the Apple server when installing if no cache server value provided
    if (args.install or args.create_mirror) and not args.pkg_server:
        args.pkg_server = args.feed_base_url

    # Process the cache server argument with custom checks but only if installing/creating a mirror
    if args.cache_server and args.install:
        prefix = opts_map["cache_server"]

        if not args.cache_server == "auto":
            try:
                validate_caching_server_url(args.cache_server)
            except CachingServerMissingSchemeException as me:
                parser.error(f"argument {prefix}: parameter is {me}")
            except CachingServerSchemeException as se:
                parser.error(f"argument {prefix}: {se}")
            except CachingServerPortException as pe:
                parser.error(f"argument {prefix}: {pe}")
        elif args.cache_server == "auto":
            try:
                args.cache_server = locate_caching_server(
                    args.default_caching_server_type, args.default_caching_server_rank
                )
            except CachingServerAutoLocateException as le:
                parser.error(f"argument {prefix}: {le}")

    # The package server argument must end in '/lp10_ms3_content_2016/'
    if args.pkg_server:
        pkg_ew_str = "/lp10_ms3_content_2016/"
        prefix = opts_map["pkg_server"]
        scheme = urlparse(args.pkg_server).scheme

        if scheme not in ["http", "https"] or scheme is None:
            parser.error(f"argument {prefix}: a valid url scheme is required, either 'http' or 'https'")

        if not args.pkg_server.endswith(pkg_ew_str):
            args.pkg_server = f"{args.pkg_server.removesuffix('/')}/{pkg_ew_str}"

    return args
