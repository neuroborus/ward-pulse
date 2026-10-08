#!/usr/bin/env python3
"""Fixture gate: every JSON parses, and every golden fixture matches its schema.

The schemas are closed (`additionalProperties: false`), so a stray field, a
missing required one, or a value of the wrong shape is a contract break. Nothing
enforced them until this check existed, and a broken golden fixture only showed
up much later as a failing Rust or phone test.

The checker covers the keywords these schemas actually use, and every schema is
swept for anything else — including branches no fixture walks into, which is
where an unread rule would hide. That is why there is no third-party validator
here: the supported subset is small, and AGENTS.md keeps dependencies for what
cannot be done without them.
"""

from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]

# Which schema each golden fixture answers to. Fixtures under `providers/` are
# sanitized provider payloads and have no schema of ours to match.
FIXTURE_SCHEMAS = {
    "snapshots/dashboard_today.json": "dashboard_snapshot.schema.json",
    "snapshots/dashboard_week.json": "dashboard_snapshot.schema.json",
    "snapshots/dashboard_alerts.json": "dashboard_snapshot.schema.json",
    "snapshots/watch_dashboard_summary.json": "watch_dashboard_summary.schema.json",
    "snapshots/watch_dashboard_summary_paired.json": "watch_dashboard_summary.schema.json",
    "snapshots/plan_recovery.json": "plan_recovery.schema.json",
}

SUPPORTED = {
    "$schema", "$id", "$defs", "$ref", "title", "description",
    "type", "properties", "additionalProperties", "required", "items",
    "enum", "const", "anyOf", "allOf",
    "minimum", "maximum", "minLength", "maxLength", "maxItems", "pattern",
    "format",
}

TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "number": (int, float),
    "integer": int,
    "boolean": bool,
}


def load_schemas() -> dict[str, Any]:
    return {
        path.name: json.loads(path.read_text(encoding="utf-8"))
        for path in sorted(ROOT.glob("schemas/*.schema.json"))
    }


def resolve(ref: str, schemas: dict[str, Any], current: str) -> tuple[Any, str]:
    """A `$ref` to a local `$defs` entry, or to one in a sibling schema."""
    file_part, _, pointer = ref.partition("#")
    name = file_part or current
    node = schemas[name]
    for step in [part for part in pointer.split("/") if part]:
        node = node[step]
    return node, name


def check(
    value: Any, schema: Any, schemas: dict[str, Any], current: str, where: str
) -> list[str]:
    # Keywords are vetted by check_keywords before any fixture is read, so this
    # walk may assume it understands every node it lands on.
    if "$ref" in schema:
        target, owner = resolve(schema["$ref"], schemas, current)
        return check(value, target, schemas, owner, where)

    errors: list[str] = []
    for branch in schema.get("allOf", []):
        errors += check(value, branch, schemas, current, where)

    if "anyOf" in schema:
        attempts = [
            check(value, branch, schemas, current, where) for branch in schema["anyOf"]
        ]
        if all(attempts):
            # Say why each shape was refused: `nullableMoney` failing as
            # "matches none" sends the reader to read the schema by hand.
            reasons = "; ".join(
                attempt[0].removeprefix(where).lstrip(".: ") for attempt in attempts
            )
            errors.append(f"{where}: matches no allowed shape ({reasons})")
        return errors

    expected = schema.get("type")
    if expected is not None:
        names = expected if isinstance(expected, list) else [expected]
        if not any(matches_type(value, name) for name in names):
            return errors + [f"{where}: expected {'/'.join(names)}, got {type_name(value)}"]

    if "const" in schema and value != schema["const"]:
        errors.append(f"{where}: expected {schema['const']!r}, got {value!r}")
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{where}: {value!r} is not one of {schema['enum']}")

    if isinstance(value, str):
        errors += check_string(value, schema, where)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{where}: {value} is below minimum {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{where}: {value} is above maximum {schema['maximum']}")
    if isinstance(value, list):
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(f"{where}: {len(value)} items exceed maxItems {schema['maxItems']}")
        item_schema = schema.get("items")
        if item_schema is not None:
            for index, item in enumerate(value):
                errors += check(item, item_schema, schemas, current, f"{where}[{index}]")
    if isinstance(value, dict):
        errors += check_object(value, schema, schemas, current, where)

    return errors


def check_string(value: str, schema: Any, where: str) -> list[str]:
    errors: list[str] = []
    if "minLength" in schema and len(value) < schema["minLength"]:
        errors.append(f"{where}: shorter than minLength {schema['minLength']}")
    if "maxLength" in schema and len(value) > schema["maxLength"]:
        errors.append(f"{where}: longer than maxLength {schema['maxLength']}")
    if "pattern" in schema and not re.search(schema["pattern"], value):
        errors.append(f"{where}: {value!r} does not match {schema['pattern']}")
    # `format` is an annotation in JSON Schema; instants are asserted anyway,
    # because a timestamp the shells cannot parse is the bug this gate is for.
    if schema.get("format") == "date-time":
        try:
            datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            errors.append(f"{where}: {value!r} is not a date-time")
    return errors


def check_object(
    value: dict[str, Any], schema: Any, schemas: dict[str, Any], current: str, where: str
) -> list[str]:
    errors: list[str] = []
    properties = schema.get("properties", {})
    for name in schema.get("required", []):
        if name not in value:
            errors.append(f"{where}: missing required '{name}'")
    if schema.get("additionalProperties") is False:
        for name in value:
            if name not in properties:
                errors.append(f"{where}: unexpected property '{name}'")
    for name, item in value.items():
        if name in properties:
            errors += check(item, properties[name], schemas, current, f"{where}.{name}")
    return errors


def matches_type(value: Any, name: str) -> bool:
    if name == "null":
        return value is None
    if name == "boolean":
        return isinstance(value, bool)
    if name in ("number", "integer") and isinstance(value, bool):
        return False
    # Stricter than JSON Schema on purpose: it counts `1240.0` as an integer,
    # while serde refuses it into an `i64`. The gate protects the readers of
    # these fixtures, and Rust is the strictest of them.
    return isinstance(value, TYPES[name])


def type_name(value: Any) -> str:
    if value is None:
        return "null"
    for name, kind in TYPES.items():
        if name != "integer" and isinstance(value, kind):
            return "boolean" if isinstance(value, bool) else name
    return type(value).__name__


def check_keywords(name: str, node: Any, where: str = "") -> list[str]:
    """Sweep every schema node, not only the ones a fixture walks into.

    An optional property no fixture carries is exactly where an unread rule
    would hide, and it would stay hidden until the day something depended on it.
    """
    if not isinstance(node, dict):
        return []
    extra = set(node) - SUPPORTED
    errors = [f"{name}{where}: unsupported keywords {sorted(extra)}"] if extra else []
    for key, value in node.items():
        if key in ("properties", "$defs"):
            for child, sub in value.items():
                errors += check_keywords(name, sub, f"{where}/{key}/{child}")
        elif key == "items":
            errors += check_keywords(name, value, f"{where}/items")
        elif key in ("anyOf", "allOf"):
            for index, sub in enumerate(value):
                errors += check_keywords(name, sub, f"{where}/{key}[{index}]")
    return errors


# The shells cannot import the schema, so each repeats its version number. A
# mismatch is silent at build time and total at run time: the Wear store drops
# every payload whose version it does not recognise.
SCHEMA_VERSION_USES = {
    "apps/wear_android/app/src/main/java/app/wardpulse/wear/data/WatchSummaryStore.kt":
        r"SCHEMA_VERSION = (\d+)",
    "apps/phone_flutter/lib/sync/watch_sync_service.dart":
        r"'schemaVersion': (\d+)",
}


def check_schema_version(schemas: dict[str, Any]) -> list[str]:
    """The one number the phone, the watch, and the contract must agree on."""
    summary = schemas["watch_dashboard_summary.schema.json"]
    expected = summary["properties"]["schemaVersion"]["const"]
    errors: list[str] = []
    for relative, pattern in sorted(SCHEMA_VERSION_USES.items()):
        source = (ROOT / relative).read_text(encoding="utf-8")
        found = re.search(pattern, source)
        if found is None:
            errors.append(f"{relative}: no schema version found by /{pattern}/")
        elif int(found.group(1)) != expected:
            errors.append(
                f"{relative}: schema version {found.group(1)}, contract says {expected}"
            )
    return errors


def report(errors: list[str]) -> int:
    for error in errors:
        print(error)
    return 1


def main() -> int:
    paths = sorted(ROOT.glob("schemas/*.json")) + sorted(ROOT.glob("fixtures/**/*.json"))
    errors: list[str] = []
    for path in paths:
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as failure:
            # Name the file: a decoder message alone says "line 48" of nothing.
            errors.append(f"{path.relative_to(ROOT)}: {failure}")
    if errors:
        # Nothing below can be trusted while a file refuses to parse.
        return report(errors)

    # `load_schemas` reads `*.schema.json`; a schema named anything else would
    # sit here unswept, which is the same silence this gate is against.
    for path in sorted(ROOT.glob("schemas/*.json")):
        if not path.name.endswith(".schema.json"):
            errors.append(
                f"schemas/{path.name}: not named *.schema.json, so nothing reads it"
            )

    schemas = load_schemas()
    errors += check_schema_version(schemas)
    for name, schema in schemas.items():
        errors += check_keywords(name, schema)
    # A golden fixture nobody mapped is the quiet failure this gate exists to
    # stop: it would look validated because the run stayed green.
    for path in sorted(ROOT.glob("fixtures/snapshots/*.json")):
        relative = f"snapshots/{path.name}"
        if relative not in FIXTURE_SCHEMAS:
            errors.append(f"{relative}: not listed in FIXTURE_SCHEMAS, so nothing checks it")

    for relative, schema_name in sorted(FIXTURE_SCHEMAS.items()):
        fixture = ROOT / "fixtures" / relative
        instance = json.loads(fixture.read_text(encoding="utf-8"))
        errors += check(instance, schemas[schema_name], schemas, schema_name, relative)

    if errors:
        return report(errors)

    print(f"validated {len(paths)} json files, {len(FIXTURE_SCHEMAS)} against schemas")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
