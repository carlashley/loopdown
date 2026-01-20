import signal

from collections.abc import Callable


Handler = Callable[[int, object], None]


def install_termination_handlers(*, raise_kb_interrupt: bool = True) -> None:
    """install signal handlers so SIGTERM triggers clean shutdown.
    :param raise_kb_interrupt: SIGTERM raises 'KeyboardInterrupt' if 'True' so it follows
                               the same cleanup path as CTRL+C; if 'False', raises SystemExit(143)"""
    def _handle_sigterm(signum: int, frame: object) -> None:
        if raise_kb_interrupt:
            raise KeyboardInterrupt

        raise SystemExit(143)

    signal.signal(signal.SIGTERM, _handle_sigterm)
