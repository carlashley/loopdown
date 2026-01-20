import logging
import sys

from loopdown.arguments import build_arguments
from loopdown.base.context import LoopdownContext
from loopdown.utils.flock_utils import lock_execution, AlreadyRunningError
from loopdown.logger.logging_utils import configure_logging
from loopdown.utils.signal_utils import install_termination_handlers

log = logging.getLogger(__name__)


def main():
    with lock_execution(app_name=__name__):
        args = build_arguments()
        configure_logging(args.log_level, path=args.log_file, quiet=args.quiet)

        context = LoopdownContext(args=args)
        context.audit_start()
        context.process_content()
        context.audit_stop()


if __name__ == "__main__":
    install_termination_handlers()

    try:
        main()
    except AlreadyRunningError:
        sys.exit(1)
    except KeyboardInterrupt:
        log.error("\nSIGINT exiting.")
        sys.exit(130)  # POSIX exit code for SIGINT
