"""Main"""
import sys

maj_r, min_r = 3, 10
major, minor, _, _, _ = sys.version_info
pyexe = sys.executable
reqd = f"{maj_r}.{min_r}"

if not (major >= maj_r and minor >= min_r):
    print(
        f"Python {major}.{minor} at {pyexe!r} is not supported, minimum version required is Python {reqd}; exiting.",
        file=sys.stderr,
    )
    sys.exit(2)


from ldilib import Loopdown
from ldilib.clargs import arguments
from ldilib.logger import construct_logger
from ldilib.utils import debugging_info


def main() -> None:
    """Main method"""
    args = arguments()
    log = construct_logger(level=args.log_level, silent=args.silent)
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
        max_retries=args.max_retries,
        max_retry_time_limit=args.max_retry_time_limit,
        proxy_args=args.proxy_args,
        log=log,
    )

    try:
        if args.discover_plists:
            _min, _max = args.discover_plists_range
            ld.parse_discovery(_min, _max)
            sys.exit()

        processing_str = ", ".join(f"'{item}'" for item in args.apps or args.plists)
        log.info(f"Processing content for: {processing_str}")

        # Process applications if specified
        if args.apps:
            for app in args.apps:
                source_file = ld.parse_application_plist_source_file(app)

                if source_file:
                    packages = ld.parse_plist_source_file(source_file)
                    ld.parse_packages(packages)

        # Process property list metadata files if specified
        if args.plists:
            for plist in args.plists:
                source_file = ld.parse_plist_remote_source_file(plist)

                if source_file:
                    packages = ld.parse_plist_source_file(source_file)
                    ld.parse_packages(packages)

        # Clean up temporary working directory if it exists
        ld.cleanup_working_dirs()

        # Exit if there are no packages found
        if (len(ld.packages["mandatory"]) or len(ld.packages["optional"])) > 0:
            if ld.has_enough_disk_space():
                packages = sorted(
                    list(ld.packages["mandatory"].union(ld.packages["optional"])), key=lambda x: x.download_name
                )
                total_packages = len(packages)
                error_packages = 0
                instf_packages = []

                for package in packages:
                    pkg = None
                    counter = f"{packages.index(package) + 1} of {total_packages}"

                    if package.status_ok:
                        if ld.dry_run:
                            prefix = "Download" if not ld.install else "Download and install"
                        elif not ld.dry_run:
                            prefix = "Downloading" if not ld.install else "Downloading and installing"
                    else:
                        prefix = "Package error"
                        error_packages += 1

                    log.info(f"{prefix} {counter} - {package}")

                    if not ld.dry_run:
                        # Force download, Will not resume partials!
                        if args.force and package.download_dest.exists():
                            package.download_dest.unlink(missing_ok=True)

                        if package.status_ok:
                            pkg = ld.get_file(package.download_url, package.download_dest, args.silent)

                        if ld.install and pkg:
                            log.info(f"Installing {counter} - {package.download_dest.name!r}")
                            installed = ld.install_pkg(package.download_dest, package.install_target)

                            if installed:
                                log.info(f"  {package.download_dest} was installed")
                            else:
                                instf_packages.append(package.download_dest.name)
                                log.error(
                                    f"  {package.download_dest} was not installed; see '/var/log/install.log' or"
                                    " '/Users/Shared/loopdown/loopdown.log' for more information."
                                )
                            package.download_dest.unlink(missing_ok=True)

            if float(error_packages) >= float(total_packages * 0.5):
                log.error(
                    "Warning: Over half the packages will not be downloaded and/or installed, please check"
                    " the log file /Users/Shared/loopdown/loopdown.log for more information."
                )
            else:
                if not ld.dry_run:
                    if instf_packages:
                        log.error(
                            "The following packages failed to install, see '/var/log/install.log' or"
                            " '/Users/Shared/loopdown/loopdown.log' for more information."
                        )
                        for pkg in instf_packages:
                            log.error(f"  - {pkg}")

                    log.info(ld)
        else:
            log.info(
                "No packages found; there may be no packages to download/install, there may be no matching"
                " application/s installed, or no matching metadata property list file/s found for processing."
            )
            sys.exit()
    except KeyboardInterrupt:
        log.info("Exiting...")
        ld.cleanup_working_dirs()


if __name__ == "__main__":
    main()
