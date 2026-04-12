"""Main."""

import logging
import sys

sys.dont_write_bytecode = True

from loopdown.arguments import build_arguments
from loopdown.context import ContextManager
from loopdown.orchestration import Orchestrate
from loopdown.utils.runtime_utils import install_termination_handlers, lock_execution, AlreadyRunningError
from loopdown.logger.logging_utils import configure_logging

log = logging.getLogger(__name__)


def main():
    """Main."""
    print(
        "Warning: this Python implementation of loopdown has been deprecated and will move to a Swift based "
        "implementation in the future.",
        file=sys.stderr,
    )

    with lock_execution(app_name=__name__):
        args = build_arguments()
        configure_logging(args.log_level, path=args.log_file, quiet=args.quiet)

        conductor = Orchestrate(ctx=ContextManager(args=args))
        conductor.process_content()


if __name__ == "__main__":
    install_termination_handlers()

    try:
        main()
    except AlreadyRunningError:
        sys.exit(1)
    except KeyboardInterrupt:
        log.error("\nSIGINT exiting.")
        sys.exit(130)  # POSIX exit code for SIGINT
