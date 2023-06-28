"""Arguments for command line use."""
import argparse

from urllib.parse import urlparse

from .arguments import arg_config
from .arguments.constructor import construct_arguments
from .arguments.validations import (
    incompatible_args,
    requires_additional_arg,
    requires_multiple_args,
    validate_core_args,
)
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
    args, parser, opts_map = construct_arguments(arg_config)

    # Convert arguments that require integer values at argument creation into strings so
    # they're the appropriate type for other internal methods/functions where string types
    # are required
    args.max_retries = str(args.max_retries)
    args.max_retry_time_limit = str(args.max_retry_time_limit)

    required_core_args = {
        "apps": args.apps,
        "create_mirror": args.create_mirror,
        "discover_plists": args.discover_plists,
        "plists": args.plists,
    }
    discovery_bad_args = {
        "apps": args.apps,
        "cache_server": args.cache_server,
        "create_mirror": args.create_mirror,
        "dry_run": args.dry_run,
        "force": args.force,
        "install": args.install,
        "mandatory": args.mandatory,
        "optional": args.optional,
        "plists": args.plists,
        "pkg_server": args.pkg_server,
        "silent": args.silent,
    }

    # Make sure the minimum required arguments are supplied
    validate_core_args(required_core_args, opts_map, parser)

    if args.discover_plists:
        # Make sure any args not usable with '--discover-plists' arg don't exist
        incompatible_args(("discover_plists", args.discover_plists), discovery_bad_args, opts_map, parser)
    elif not args.discover_plists:
        # Make sure any args that require other arguments don't exist
        discover_plists_reqd = {"discover_plists": args.discover_plists}
        mirror_install_reqd = {"create_mirror": args.create_mirror, "install": args.install}
        mand_opts_reqd = {"mandatory": args.mandatory, "optional": args.optional}
        cache_server_not_allwd = {"cache_server": args.cache_server}
        create_mirror_reqd = {"create_mirror": args.create_mirror}
        install_not_allwd = {"install": args.install}
        pkg_server_install_reqd = {"install": args.install}
        warn_threshold_reqd = {"create_mirror": args.create_mirror, "install": args.install}

        # Make sure --discover-plists-range as --discover-plists arg, this shouldn't be needed but is here
        # just in case
        for arg in [("discover_plists_range", args.discover_plists_range)]:
            requires_additional_arg(arg, discover_plists_reqd, opts_map, parser)

        # If -a/--apps or --cache-server or -f/--force, make sure --create-mirror or -i/--install are specified
        for arg in [("apps", args.apps), ("cache_server", args.cache_server), ("force", args.force)]:
            requires_multiple_args(arg, mirror_install_reqd, opts_map, parser, "or")

        # If --cache-server and --create-mirror, not allowed
        for arg in [("create_mirror", args.create_mirror)]:
            incompatible_args(arg, cache_server_not_allwd, opts_map, parser)

        # If --create-mirror or -i/--install are specified, make sure -m/--mandatory and or -o/--optional are as well
        for arg in [("create_mirror", args.create_mirror), ("install", args.install)]:
            requires_multiple_args(arg, mand_opts_reqd, opts_map, parser, "and/or")

        # If -p/--plists and --create-mirror not provided
        for arg in [("plists", args.plists)]:
            requires_additional_arg(arg, create_mirror_reqd, opts_map, parser)

        # If --pkg-server and -i/--install not provided
        for arg in [("pkg_server", args.pkg_server)]:
            requires_additional_arg(arg, pkg_server_install_reqd, opts_map, parser)

        # If -i/--install and --create-mirror or -p/--plists provided
        for arg in [("create_mirror", args.create_mirror), ("plists", args.plists)]:
            incompatible_args(arg, install_not_allwd, opts_map, parser)

        # If --default-warning-threshold and -i/--install provided
        for arg in [("default_warn_threshold", args.default_warn_threshold)]:
            requires_multiple_args(arg, warn_threshold_reqd, opts_map, parser)
        # Check the default warning threshold is > 0 < 1.0
        if args.default_warn_threshold and not 0.1 <= args.default_warn_threshold <= 1.0:
            parser.error(f"argument {opts_map}: argument value must be between 0.1 and 1.0")

        # Check if user is root when -i/--install is provided
        if args.install and not is_root():
            parser.error(f"argument {opts_map['install']}: you must be root to use this argument")

        # Handle --default-log-directory checks
        if args.default_log_directory:
            log_dir_exists = args.default_log_directory.resolve().exists()
            log_dir_is_dir = args.default_log_directory.resolve().is_dir()
            log_dir_is_syl = args.default_log_directory.resolve().is_symlink()
            path_type = "symlink" if log_dir_is_syl else "file" if not log_dir_is_dir else "directory"
            opts_str = opts_map["default_log_directory"]

            if log_dir_exists and not log_dir_is_dir:
                parser.error(f"argument {opts_str}: argument value must be a directory path, not a {path_type}")

        # Make sure args.pkg_server points to the Apple server when installing if no cache server value provided
        if (args.install or args.create_mirror) and not args.pkg_server:
            args.pkg_server = args.feed_base_url

        # Process the cache server argument with custom checks but only if installing/creating a mirror
        if args.cache_server and args.install:
            if not args.cache_server == "auto":
                try:
                    validate_caching_server_url(args.cache_server)
                except CachingServerMissingSchemeException as me:
                    parser.error(f"argument {opts_map['cache_server']}: parameter is {me}")
                except CachingServerSchemeException as se:
                    parser.error(f"argument {opts_map['cache_server']}: {se}")
                except CachingServerPortException as pe:
                    parser.error(f"argument {opts_map['cache_server']}: {pe}")
            elif args.cache_server == "auto":
                try:
                    args.cache_server = locate_caching_server(
                        args.default_caching_server_type, args.default_caching_server_rank
                    )
                except CachingServerAutoLocateException as le:
                    parser.error(f"argument {opts_map['cache_server']}: {le}")

        # The package server argument must end in '/lp10_ms3_content_2016/'
        if args.pkg_server:
            scheme = urlparse(args.pkg_server).scheme

            if scheme not in ["http", "https"] or scheme is None:
                parser.error(
                    f"argument {opts_map['pkg_server']}: a valid url scheme is required, either 'http' or 'https'"
                )

            pkg_ew_str = "/lp10_ms3_content_2016/"

            if not args.pkg_server.endswith(pkg_ew_str):
                args.pkg_server = f"{args.pkg_server.removesuffix('/')}/{pkg_ew_str}"

    return args
