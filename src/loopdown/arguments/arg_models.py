"""Models for argument parsing."""

import argparse

from dataclasses import dataclass, field
from typing import Optional


# this is a meta dataclass, only slots are required; doesn't generate __dict__; stops arbitrary attributes
# being added at runtime
@dataclass(slots=True)
class _AllExclusiveGroup:
    """Argument group where all options are exclusive."""

    title: Optional[str] = field(default=None)
    description: Optional[str] = field(default=None)
    actions: list[argparse.Action] = field(default_factory=list)
    message: Optional[str] = None


@dataclass(slots=True)
class _AnyRequiredGroup:
    """Argument group where any one (or more) option is required."""

    title: Optional[str] = field(default=None)
    description: Optional[str] = field(default=None)
    actions: list[argparse.Action] = field(default_factory=list)
    message: Optional[str] = None
