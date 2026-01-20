import argparse
import sys

from collections.abc import Iterable
from enum import Enum
from typing import overload, cast, Any, Optional, Sequence, TypeVar
from os import geteuid

from .arg_formatters import QuotedChoicesHelpFormatter
from .arg_models import _AnyRequiredGroup, _AllExclusiveGroup
from .arg_sentinels import AUTO, MISSING
from ..consts.config_consts import ConfigurationConsts


_N = TypeVar("_N")  # , bound=argparse.Namespace)


class StrictArgumentParser(argparse.ArgumentParser):
    """Strict enforce custom formatting; eliminates the default appending of 'default: %(default)s' to arguments.
    Additional implementations of:
        - custom 'one or many/all of' argument requirements (with validation)
        - custom exclusive group to provide better grouping of options in help output (with validation)
        - handle sentinels for 'nargs="?"' arguments via const=AUTO|MISSING (MISSING is validated only when argument
          is provided at the command line)"""

    def __init__(self, *args, **kwargs) -> None:
        kwargs.setdefault("formatter_class", QuotedChoicesHelpFormatter)
        super().__init__(*args, **kwargs)

        self._any_required_groups: list[_AnyRequiredGroup] = []
        self._all_exclusive_groups: list[_AllExclusiveGroup] = []

    def add_any_required_group(
        self,
        title: Optional[str] = None,
        *,
        description: Optional[str] = None,
        message: Optional[str] = None,
    ) -> argparse._ArgumentGroup:
        """Create a group where at least one member argument must be provided.

        This is like a normal argument group for help output, validated automatically."""
        grp = self.add_argument_group(title, description)
        meta = _AnyRequiredGroup(title=title, description=description, message=message)

        # monkey patch grp.add_argument so we can record the actions added to it
        orig_add_arg = grp.add_argument

        def add_argument(*args, **kwargs) -> argparse.Action:
            action = orig_add_arg(*args, **kwargs)
            meta.actions.append(action)

            return action

        grp.add_argument = add_argument  # type: ignore[assignment]
        self._any_required_groups.append(meta)

        return grp

    def add_exclusive_group(
        self,
        title: Optional[str] = None,
        *,
        description: Optional[str] = None,
        message: Optional[str] = None,
    ) -> argparse._ArgumentGroup:
        """Create a group where all options are exclusive of each other.

        This is like a normal argument group for help output, validated automatically."""
        grp = self.add_argument_group(title, description)
        meta = _AllExclusiveGroup(title=title, description=description, message=message)

        # monkey patch grp.add_argument so we can record the actions added to it
        orig_add_arg = grp.add_argument

        def add_argument(*args, **kwargs) -> argparse.Action:
            action = orig_add_arg(*args, **kwargs)
            meta.actions.append(action)

            return action

        grp.add_argument = add_argument  # type: ignore[assignment]
        self._all_exclusive_groups.append(meta)

        return grp

    def add_subparsers(self, *args, **kwargs):
        sp = super().add_subparsers(*args, **kwargs)

        # ensure every subparser defaults to our 'QuotedChoicesHelpFormatter' unless explicitly overridden
        orig = sp.add_parser

        def add_parser(name, **sp_kwargs):
            sp_kwargs.setdefault("formatter_class", QuotedChoicesHelpFormatter)

            return orig(name, **sp_kwargs)

        sp.add_parser = add_parser  # monkey patch action method

        return sp

    @overload
    def parse_args(self, args: Sequence[str] | None = ..., namespace: None = ...) -> argparse.Namespace:
        ...

    @overload
    def parse_args(self, args: Sequence[str] | None, namespace: _N) -> _N:
        ...

    @overload
    def parse_args(self, *, namespace: _N) -> _N:
        ...

    def parse_args(self, args: Sequence[str] | None = None, namespace: _N | None = None) -> argparse.Namespace | _N:
        """Implements specific validations for optional required group arguments."""
        # resolve argv list argparse will actuall parse
        argv: Sequence[str] = sys.argv[1:] if args is None else args

        # print usage when no args provided
        if len(argv) == 0:
            self.print_usage(sys.stderr)
            sys.exit(1)

        ns = super().parse_args(args=args, namespace=namespace)
        ns_for_validation = cast(argparse.Namespace, ns)

        # normalize various arguments before validation, such as '--scan' flipping '-r/--req' and '-o/--opt' to 'True'
        self._normalize_scan_mode(ns_for_validation)

        # normalize download path when installing package content to avoid deleting download-only content
        self._normalize_deployment_download_path(ns_for_validation)

        self._validate_scan_exclusive(ns_for_validation, argv=argv)
        self._validate_required_apps(ns_for_validation)
        self._validate_all_exclusive_groups(ns_for_validation)
        self._validate_any_required_groups(ns_for_validation)
        self._validate_required_values(ns_for_validation)
        self._validate_root_required(ns_for_validation)

        # If a concrete namespace object was provided, preserve that type for mypy.
        if namespace is not None:
            return cast(_N, ns)

        return ns

    def _check_value(self, action: argparse.Action, value: Any) -> None:
        """Customize the 'invalid choice' error message formatting. All other argparse behaviour unchanged."""
        choices = getattr(action, "choices", None)

        if choices is None:
            return None

        # keep argparse semantics: membership check against action.choices
        if value in choices:
            return None

        msg = f"invalid choice: {value!r} (choose from {self._format_choices_for_error(choices)})"
        raise argparse.ArgumentError(action, msg)

    def _format_choices_for_error(self, choices: Iterable[Any]) -> str:
        """Format choices like: 'a', 'b', 'c', or 'd'."""
        # convert choices to display strings (handle StrEnum/Enum etc)
        parts = [repr(str(c.value if isinstance(c, Enum) else c)) for c in choices]

        if not parts:
            return ""

        if len(parts) == 1:
            return parts[0]

        if len(parts) == 2:
            return f"{parts[0]} or {parts[1]}"

        return f"{', '.join(parts[:-1])} or {parts[-1]}"

    def _is_present(self, ns: argparse.Namespace, action: argparse.Action) -> bool:
        """Return True if the option was supplied on the command line.
        Works for:
            - store_true/store_false
            - store (default None)
            - nargs="?" with const sentinel (AUTO/MISSING)
            - append (list) if you use default None"""
        val = getattr(ns, action.dest, None)

        # standard absent or store_true absent values
        if val in (None, False):
            return False

        if val is MISSING:
            return True  # explicitly present but missing value

        return True

    def _normalize_deployment_download_path(self, ns: argparse.Namespace) -> None:
        """Normalize the download path back to '/tmp/loopdown'. Enforced when '--download-only' is absent."""
        if getattr(ns, "action", "") == "download":
            return None

        setattr(ns, "destination", ConfigurationConsts.DEFAULT_DOWNLOAD_DEST)

    def _normalize_scan_mode(self, ns: argparse.Namespace) -> None:
        """Applies implied defaults when '--scan' is used at the command line by automatically defaulting
        '-r/--req' and '-o/--opt' both to True, and '-a/--apps' to scan for all apps."""
        if not getattr(ns, "scan", False):
            return None

        # '--scan' implies both '-r/--req' and '-o/--opt' are enabled
        setattr(ns, "required", True)
        setattr(ns, "optional", True)

        # '--scan' implies all apps (so '-a/--apps' isn't required)
        setattr(ns, "applications", AUTO)

        # set dry_run for safety
        setattr(ns, "dry_run", True)

    def _validate_all_exclusive_groups(self, ns: argparse.Namespace) -> None:
        """Perform validation of any required group arguments. Is none or one of the argument group present."""
        for grp in self._all_exclusive_groups:
            # present = [a for a in grp.actions if getattr(ns, a.dest, None) not in (None, False)]
            present = [a for a in grp.actions if self._is_present(ns, a)]

            if len(present) <= 1:
                continue

            opts: list[str] = []

            for a in grp.actions:
                opt_str = "/".join(a.option_strings)
                opts.extend([opt_str])

            msg = grp.message or f"only one of {', '.join(opts)} is allowed"
            self.error(msg)

    def _validate_any_required_groups(self, ns: argparse.Namespace) -> None:
        """Perform validation of any required group arguments. Is either/or/all of the argument group present.
        An option is considered present if its destination isn't 'default/None/False'; this preserves functionality
        for 'store_true/store/append/etc' actions."""
        for grp in self._any_required_groups:
            # if any(getattr(ns, a.dest, None) not in (None, False) for a in grp.actions):
            if any(self._is_present(ns, a) for a in grp.actions):
                continue

            opts: list[str] = []

            for a in grp.actions:
                opts.extend(a.option_strings)

            msg = grp.message or f"at least one of {', '.join(opts)} is required"
            self.error(msg)

    def _validate_required_apps(self, ns: argparse.Namespace) -> None:
        """Validates the '-a/--apps' argument is specified"""
        if getattr(ns, "applications", None) is None:
            self.error("the following arguments are required: -a/--apps")

    def _validate_required_values(self, ns: argparse.Namespace) -> None:
        """Validate any option that was provided without its required value; only applies to options that are
        created with nargs='?' and const=MISSING."""
        for action in self._actions:
            # only consider optional arguments (ignores positionals)
            if not getattr(action, "option_strings", None):
                continue

            # only consider args that opted into this convention
            if getattr(action, "nargs", None) != "?":
                continue

            if getattr(action, "const", None) is not MISSING:
                continue

            dest = action.dest

            if getattr(ns, dest, None) is not MISSING:
                continue

            # build error string "argument -a/--argument: expected 1 argument"
            opt = "/".join(action.option_strings) if action.option_strings else dest
            self.error(f"argument {opt}: expected 1 argument")

    def _validate_root_required(self, ns: argparse.Namespace) -> None:
        """Require effective UID 0 (root) unless arguments that don't require it are specified."""
        if getattr(ns, "dry_run", False):
            return None

        if getattr(ns, "action", "") == "download":
            return

        if geteuid() != 0:
            self.error("you must be root (or run with sudo) to use this command unless -n/--dry-run is set")

    def _validate_scan_exclusive(self, ns: argparse.Namespace, *, argv: Sequence[str]) -> None:
        """Validate that '--scan' is exclusive; no other options may be used except for a small set of global
        flags such as '-l/--log-level', '-v/--version', '-h/--help', etc."""
        if not getattr(ns, "scan", False):
            return None

        allowed: set[str] = {
            "--scan",  # need to allow this one! :)
            "-h", "--help",
            "-v", "--version",
            "-l", "--log-level",
            "-n", "--dry-run",  # this is set in the normalization of '--scan' but allow just in case
        }

        # map option string to Action (argparse internal, but stable and widely used in this class)
        opts_to_action: dict[str, argparse.Action] = dict(self._option_string_actions)

        # track actions we've already reported, so '-r' and '--req' etc become one entry
        illegal_actions: dict[int, argparse.Action] = {}
        illegal_unknown: list[str] = []

        for tok in argv:
            if tok == "--":
                break

            if not tok.startswith("-"):
                continue

            # support '--opt=value' forms
            opt = tok.split("=", 1)[0]

            # reject short opts like "-nor" (they're not used here)
            if opt.startswith("-") and not opt.startswith("--") and len(opt) > 2:
                illegal_unknown.append(opt)
                continue

            if opt in allowed:
                continue

            action = opts_to_action.get(opt)

            if action is None:
                # might be something like '-W' from Python or something unexpected, we'll show the raw token
                illegal_unknown.append(opt)
                continue

            illegal_actions[id(action)] = action

        if not illegal_actions and not illegal_unknown:
            return None

        def fmt_action(a: argparse.Action) -> str:
            # prefer stable ordering: short ('-a'), then long ('--apps'); argparse preserves add_argument order
            # usually this already comes as ['-a', '--apps'], etc
            if a.option_strings:
                return "/".join(a.option_strings)

            return a.dest  # fallback, should be rare

        parts: list[str] = []
        parts.extend(fmt_action(a) for a in illegal_actions.values())
        parts.extend(illegal_unknown)

        # stable and readable message
        self.error(f"--scan cannot be used with {', '.join(parts)}")
