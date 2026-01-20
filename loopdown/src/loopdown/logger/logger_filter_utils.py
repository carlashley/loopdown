import logging


class ExactLevelFilter(logging.Filter):
    """Allow only records where levelno matches a single logging level.
    :param levelno: exact numeric logging level to allow, for example 'logging.INFO'"""

    def __init__(self, levelno: int) -> None:
        super().__init__()
        self._levelno = int(levelno)

    def filter(self, record: logging.LogRecord) -> bool:
        """Validate record levelno matches the levelno we're allowing.
        :param record: log record instance"""
        return record.levelno == self._levelno


class AnyOfLevelsFilter(logging.Filter):
    """Allow only records whose levelno matches one of the provided levels.
    :param levelnos: numeric levels to allow, for example [logging.WARNING, logging.INFO, logging.DEBUG]"""

    def __init__(self, levelnos: list[int] | tuple[int, ...]) -> None:
        super().__init__()
        self._levelnos = set(int(ln) for ln in levelnos)

    def filter(self, record: logging.LogRecord) -> bool:
        """Validate record levelno matches the levelnos we're allowing.
        :param record: log record instance"""
        return record.levelno in self._levelnos
