"""Main"""
import sys

maj_r, min_r = 3, 10
major, minor, _, _, _ = sys.version_info
pyexe = sys.executable
reqd = f"{maj_r}.{min_r}"

if not (major >= maj_r and minor >= min_r):
    msg = f"Python {major}.{minor} at {pyexe!r} is not supported, minimum version required is Python {reqd}; exiting."
    print(msg, file=sys.stderr)
    sys.exit(2)


from urllib.parse import urlparse  # noqa

from ldilib import Loopdown  # noqa
from ldilib.clargs import arguments  # noqa
from ldilib.logger import construct_logger  # noqa
from ldilib.utils import debugging_info  # noqa


def main() -> None:
    """Main method"""
    args = arguments()
    log = construct_logger(level=args.log_level, dest=args.default_log_directory, silent=args.silent)
    log.debug(debugging_info(args))

    ld = Loopdown(
        dry_run=args.dry_run,
        mandatory=args.mandatory,
        optional=args.optional,
        apps=args.apps,
        plists=args.plists,
        cache_server=args.cache_server,
        pkg_server=args.pkg_server,
        create_mirror=args.create_mirror,
        install=args.install,
        force=args.force,
        silent=args.silent,
        feed_base_url=args.feed_base_url,
        default_packages_download_dest=args.default_packages_download_dest,
        default_working_download_dest=args.default_working_download_dest,
        default_log_directory=args.default_log_directory,
        max_retries=args.max_retries,
        max_retry_time_limit=args.max_retry_time_limit,
        proxy_args=args.proxy_args,
        log=log,
    )
    ld.cleanup_working_dirs()

    try:
        if args.discover_plists:
            ld.parse_discovery(args.discover_plists_range)
            sys.exit()
        if not args.discover_plists:
            processing_str = ", ".join(f"'{item}'" for item in args.apps or args.plists)
            processing_msg = f"Processing content for: {processing_str}"

            if args.pkg_server:
                url = urlparse(args.pkg_server)
                processing_msg = f"{processing_msg} via '{url.scheme}://{url.netloc}'"

            if args.cache_server:
                processing_msg = f"{processing_msg} using caching server '{args.cache_server}'"

            log.info(processing_msg)
            ld.process_metadata(args.apps, args.plists)
            ld.cleanup_working_dirs()

            if not ld.has_packages:
                log.info(ld)
                sys.exit()

            has_freespace, disk_usage_message = ld.has_enough_disk_space()
            disk_usage_message = f"{disk_usage_message}; {'passes' if has_freespace else 'fails'}"

            if has_freespace:
                log.info(f"{disk_usage_message} disk usage check")
                packages = ld.sort_packages()
                errors, install_failures = ld.download_or_install(packages)

                if not ld.generate_warning_message(errors, len(packages), args.default_warn_threshold):
                    log.info(ld)
                else:
                    log_fp = args.default_log_directory.joinpath("loopdown.log")
                    prefix = "Warning: A number of packages will not be downloaded and/or installed, please check"
                    log.error(f"{prefix} '{log_fp}' for more information")
                    sys.exit(12)
            else:
                if args.install or args.create_mirror:
                    log.info(f"{disk_usage_message} disk usage check")
                    sys.exit(3)
    except KeyboardInterrupt:
        ld.cleanup_working_dirs()


if __name__ == "__main__":
    main()
