"""Helpers specifically for arguments."""
# pylint: disable=inconsistent-return-statements

import argparse

from ..utils.validators import validate_url

AUTO = object()  # sentinel for automatic cache server discovery
MISSING = object()  # sentinel for missing mirror server value

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

        raw = values
        err = validate_url(raw, reqd_scheme="http", validate_port=True)

        if err:
            raise argparse.ArgumentError(self, err)

        setattr(namespace, self.dest, raw)


class MirrorServer(argparse.Action):
    """Implements value for mirror server argument."""

    def __call__(self, parser, namespace, values, option_string=None):
        # nargs="?" + const=<sentinel> means:
        #  - values == self.const when user passed argument with no value
        #  - values is a string when user provided a value
        # in this instance, the sentinel is used to flag the value is missing so
        # we only do validation of value checks if the arg is specified at command line
        if values is self.const:
            # store a truthy sentinel so exclusive group validation fires first;
            setattr(namespace, self.dest, MISSING)
            return None

        raw = values
        err = validate_url(raw, reqd_scheme="https", validate_port=False)

        if err:
            raise argparse.ArgumentError(self, err)

        setattr(namespace, self.dest, raw)
