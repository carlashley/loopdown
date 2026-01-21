import logging

from collections.abc import Iterable, Mapping
from dataclasses import fields, is_dataclass
from functools import cached_property
from typing import Any

from ..models.protocol_types import AsDict

log = logging.getLogger(__name__)


def iter_dataclass_properties(cls: type) -> Iterable[str]:
    """Iterate dataclass properties and yield @property and @cached_property decorated methods as string value.
    Note: this intentionally only inspects 'cls.__dict__'; the MRO is not walked; if subclassed dataclasses
          are introduced in the future and inherited properties should be included, update this function to
          iterate over 'cls.__mro__': for base in cls.__mro__: for name, obj in base.__dict__.items():...
    :param cls: class type"""
    for name, obj in cls.__dict__.items():
        if isinstance(obj, (property, cached_property)):
            yield name


def serialize_value(value: Any) -> Any:
    """Serialize a value for dataclass_to_dict without performing JSON coercion.
    :param value: value"""
    if value is None:
        return None

    # Prefer explicit serialization hook.
    if isinstance(value, AsDict):
        return value.as_dict()

    # Dataclasses without as_dict(): recurse field-wise.
    if is_dataclass(value):
        return dataclass_to_dict(value, include_properties=False)

    # Containers
    if isinstance(value, Mapping):
        return {k: serialize_value(v) for k, v in value.items()}

    if isinstance(value, (list, tuple, set)):
        return [serialize_value(v) for v in value]

    # Leave everything else as-is; json.dumps(default=str) can handle later.
    return value


def dataclass_to_dict(self, *, include_properties: bool = True) -> dict[str, Any]:
    """Walk an instance of a dataclass ('self') and return a dictionary representation.
    If this is going to be converted to JSON, don't forget to use json.dumps(data, default=str)
    Fields that are flagged 'repr=False' are not serialized.
    :param self: instance of dataclass to convert
    :param include_properties: include all '@property' and '@cached_property' decorated methods; default True"""
    if not is_dataclass(self):
        raise TypeError("dataclass_to_dict() requires a dataclass instance")

    self_dict: dict[str, Any] = {}

    for fld in fields(self):
        if not fld.repr:
            continue

        if fld.name.startswith("_"):
            continue  # skip hidden internal attrs

        self_dict[fld.name] = serialize_value(getattr(self, fld.name))

    # iterate property/cached_property decorated methods
    if include_properties:
        for attr in iter_dataclass_properties(type(self)):
            if attr in self_dict:
                continue  # don't write over existing names/avoid collision

            if attr.startswith("_"):
                continue  # skip hidden internal attrs

            try:
                self_dict[attr] = getattr(self, attr)
            except Exception as e:
                log.debug(f"Property serialization failed: {type(self).__name__}.{attr}: {str(e)}")

    return self_dict
