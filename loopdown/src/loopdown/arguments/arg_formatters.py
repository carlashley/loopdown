import argparse
import textwrap


class QuotedChoicesHelpFormatter(argparse.ArgumentDefaultsHelpFormatter):
    """Help formatter that prints '%(choices)s' and '%(default)s' wrapped in single quotes."""

    def _expand_help(self, action):
        # build the mapping used for %-substitution in 'action.help'
        params = dict(vars(action), prog=self._prog)
        help_text = action.help

        # format choices -> 'a', 'b', 'c'
        if action.choices is not None and "%(choices)s" in help_text:
            try:
                params["choices"] = ", ".join(f"'{c}'" for c in action.choices)
            except TypeError:
                # fallback if choices isn't iterable in the expected way
                params["choices"] = f"'{action.choices}'"

        if "%(default)s" in help_text:
            # format default 'value'; wraps all default values in quotes for prettification/separation
            # of argument value from normal help text
            default = getattr(action, "default", argparse.SUPPRESS)

            if default is not argparse.SUPPRESS and default is not None:
                if isinstance(default, (list, tuple, set)):
                    params["default"] = ", ".join(f"'{item}'" for item in default)
                else:
                    params["default"] = f"'{default}'"

            if help_text is None:
                return None

        return help_text % params

    def _fill_text(self, text: str, width: int, indent: str) -> str:
        """Custom implement description/epilogues, preserve explicit newlines while still wrapping and applying
        indentation."""
        lines: list[str] = []

        for raw in text.splitlines():
            if not raw.strip():
                lines.append("")  # blank line
                continue

            wrapped = textwrap.fill(raw, width=width, initial_indent=indent, subsequent_indent=indent)
            lines.append(wrapped[len(indent):] if wrapped.startswith(indent) else wrapped)

        return "\n".join(indent + ln if ln else "" for ln in lines)

    def _format_action_invocation(self, action):
        # positional? defer to default behaviour
        if not action.option_strings:
            return super()._format_action_invocation(action)

        # join option strings without repeating the metavar per flag
        opts = ", ".join(action.option_strings)

        # ask argparse to build the args string (respects nargs, metavar, tuples, etc)
        args_str = self._format_args(action, self._get_default_metavar_for_optional(action))

        return f"{opts} {args_str}" if args_str else opts

    def _split_lines(self, text: str, width: int) -> list[str]:
        """Custom implement split lines to allow for custom formatting."""
        # if '\n' is in the text, treat each line as its own wrap unit.
        if "\n" in text:
            out: list[str] = []

            for ln in text.splitlines():
                if not ln.strip():
                    out.append("")  # keep blank lines
                    continue

                out.extend(textwrap.wrap(ln, width=width))
            return out

        return super()._split_lines(text, width)
