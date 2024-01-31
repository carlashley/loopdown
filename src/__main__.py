from ldilib import arguments
from ldilib.logger import construct_logger


def main() -> None:
    """Main method"""
    args = arguments.clapper()
    log = construct_logger(level=args.log_level, dest=args.default_log_directory, silent=args.silent)

    try:
        log(args)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
