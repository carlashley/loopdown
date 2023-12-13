"""Argument constructor."""
import argparse
import sys

from typing import Any
from .. import _version_string as vers_str


def construct_arguments(config: list[dict[str, Any]]) -> argparse.ArgumentParser:
    """Internal constructor of the command line arguments.
    :param config: a list of dictionary objects representing argument configuration"""
    desc = (
        "loopdown can be used to download, install, mirror, or discover information about the additional "
        "audio content that Apple provides for the audio editing/mixing software programs GarageBand, LogicPro X "
        ", and MainStage3."
    )
    help_parser = argparse.ArgumentParser(description=desc, epilog=vers_str, add_help=False)
    help_parser.add_argument("--advanced-help", required=False, action="store_true", dest="advanced_help")
    help_args, _ = help_parser.parse_known_args()

    opts_map = {}
    parser = argparse.ArgumentParser(description=desc, epilog=vers_str, parents=[help_parser])
    exclusive_groups = {
        "apps": parser.add_mutually_exclusive_group(),
        "optn": parser.add_mutually_exclusive_group(),
        "down": parser.add_mutually_exclusive_group(),
    }

    for c in config:
        args = c.get("args")
        kwargs = c.get("kwargs")
        choices = kwargs.get("choices")
        default = kwargs.get("default")
        choices_tgt = "(choices)"
        default_tgt = "(default)"
        help_str = kwargs.get("help")
        excl_parser = c.get("parser")
        opts_map[kwargs["dest"]] = "/".join(args)

        if help_str:
            if choices and choices_tgt in help_str:
                first_choice_str = ", ".join(f"'{c}'" for c in choices[0:-1])
                choice_str = f"{first_choice_str}, or '{choices[-1]}'"
                help_str = help_str.replace(choices_tgt, choice_str)

            if default and default_tgt in help_str:
                if isinstance(default, (list, set, tuple)):
                    default_str = ", ".join(f"'{d}'" for d in default)
                else:
                    default_str = f"'{default}'"

                help_str = help_str.replace(default_tgt, default_str)

            kwargs["help"] = help_str

        if c.get("hidden", False) and not help_args.advanced_help:
            kwargs["help"] = argparse.SUPPRESS

        try:
            exclusive_groups[excl_parser].add_argument(*args, **kwargs)
        except KeyError:
            parser.add_argument(*args, **kwargs)

    if not len(sys.argv) > 1 or help_args.advanced_help:
        parser.print_help(sys.stderr)
        sys.exit()

    args = parser.parse_args()
    return (args, parser, opts_map)
