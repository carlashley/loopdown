import json

from typing import Any

from ..utils.dataclass_utils import dataclass_to_dict


class AsJsonMixin:
    """Json Mixin for dataclasses that have 'as_dict' and 'as_json' methods."""

    def as_dict(self, *, include_properties: bool = True) -> dict[str, Any]:
        """Return a dictionary representation of the object.
        :param include_properties: include all '@property' and '@cached_property' decorated methods; default True"""
        self_dict = dataclass_to_dict(self, include_properties=include_properties)

        return self_dict

    def as_json(self, *, include_properties: bool = True) -> str:
        """Return a JSON serialization of the object.
        :param include_properties: include all '@property' and '@cached_property' decorated methods; default True"""
        self_dict = self.as_dict(include_properties=include_properties)

        return json.dumps(self_dict, ensure_ascii=False, default=str)
