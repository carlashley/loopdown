import argparse

from collections.abc import Sequence
from typing import Optional

from ..utils.normalizers import normalize_caching_server_url
from ..utils.validators import validate_url


class AutoChoices(argparse.Action):
    """Implements an argument option where an auto mode is used or choices are available."""
    def __init__(self, *args, allowed: Optional[Sequence[str]] = None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.allowed = tuple(allowed or ())
        self.choices = self.allowed  # so %(choices)s works in help

    def __call__(self, parser, namespace, values, option_string=None):
        if values is self.const or (isinstance(values, list) and not values):
            setattr(namespace, self.dest, self.choices)
            return None

        # with nargs="*" argparse will pass a list (possibly empty)
        # with nargs="?" it will pass str
        if isinstance(values, str):
            items = [values]
        else:
            items = list(values)  # copy

        allowed = set(self.choices or ())
        invalid = tuple(v for v in items if v not in allowed)

        if invalid:
            allowed_txt = ", ".join(repr(c) for c in allowed)
            bad_txt = ", ".join(repr(v) for v in invalid)
            raise argparse.ArgumentError(self, f"invalid choice(s): {bad_txt} (choose from {allowed_txt})")

        setattr(namespace, self.dest, items)


class CachingServer(argparse.Action):
    """Implements optional value for caching server argument, handling three states:
        - 'auto' (auto discover)
        - 'explicit' (manually provided)
        - 'off' (argument not provided)"""

    def __call__(self, parser, namespace, values, option_string=None):
        # nargs="?" + const=<sentinel> means:
        #  - values == self.const when user passed argument with no value
        #  - values is a string when user provided a value
        if values is self.const:
            setattr(namespace, self.dest, "auto")
            return None

        if isinstance(values, (list, tuple)):
            raw = "".join(values)
        else:
            raw = values

        normalized_value = normalize_caching_server_url(raw)
        setattr(namespace, self.dest, normalized_value)


class MirrorServer(argparse.Action):
    """Implements value for mirror server argument."""

    def __call__(self, parser, namespace, values, option_string=None):
        # nargs="?" + const=<sentinel> means:
        #  - values == self.const when user passed argument with no value
        #  - values is a string when user provided a value
        # in this instance, the sentinel is used to flag the value is missing so
        # we only do validation of value checks if the arg is specified at command line
        if values is self.const:
            setattr(namespace, self.dest, values)
            return None

        # if isinstance(values, (list, tuple)):
        #     raw = "".join(values)
        # else:
        raw = values

        err = validate_url(raw, reqd_scheme="https", validate_port=False)

        if err:
            raise argparse.ArgumentError(self, err)

        setattr(namespace, self.dest, raw)
