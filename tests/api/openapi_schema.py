"""Turns OpenAPI 3.0 component schemas into JSON Schema validators (handles `nullable`)."""
from __future__ import annotations

import copy
from functools import lru_cache
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

SPEC_PATH = Path(__file__).resolve().parents[2] / "outsystems" / "api" / "weather-api.openapi.yaml"


def _nullable_to_jsonschema(node):
    if isinstance(node, dict):
        node = {k: _nullable_to_jsonschema(v) for k, v in node.items()}
        if node.pop("nullable", False):
            if "type" in node:
                node["type"] = [node["type"], "null"]
            if "enum" in node:
                node["enum"] = [*node["enum"], None]
        node.pop("example", None)
        return node
    if isinstance(node, list):
        return [_nullable_to_jsonschema(v) for v in node]
    return node


@lru_cache
def spec() -> dict:
    return yaml.safe_load(SPEC_PATH.read_text(encoding="utf-8"))


@lru_cache
def _registry() -> Registry:
    doc = _nullable_to_jsonschema(copy.deepcopy(spec()))
    return Registry().with_resource("weather-api", Resource.from_contents(doc, default_specification=DRAFT202012))


def validator_for(component: str, array: bool = False) -> Draft202012Validator:
    ref = {"$ref": f"weather-api#/components/schemas/{component}"}
    schema = {"type": "array", "items": ref} if array else ref
    return Draft202012Validator(schema, registry=_registry(), format_checker=Draft202012Validator.FORMAT_CHECKER)


def assert_conforms(body, component: str, array: bool = False) -> None:
    errors = sorted(validator_for(component, array).iter_errors(body), key=lambda e: list(e.path))
    assert not errors, "\n".join(f"{list(e.path)}: {e.message}" for e in errors[:10])
