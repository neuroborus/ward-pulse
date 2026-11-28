"""Isolated regressions against the actual fixture validator, including the OLD module."""

from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import stat
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("validate_json", Path(__file__).with_name("validate_json.py"))
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)
SOURCE_FIXTURE_SCHEMAS = dict(validator.FIXTURE_SCHEMAS)

SUMMARY = "snapshots/watch_dashboard_summary.json"
SCHEMA = "watch_dashboard_summary.schema.json"
ORDERED = "snapshots/watch_dashboard_summary_v10_demo.json"
ORDERED_SCHEMA = "watch_dashboard_summary_v10.schema.json"
WEAR_STORE = "apps/wear_android/app/src/main/java/app/wardpulse/wear/data/WatchSummaryStore.kt"
PHONE_SENDER = "apps/phone_flutter/lib/sync/watch_sync_service.dart"
NATIVE_SENDER = (
    "apps/phone_flutter/plugins/ward_pulse_watch_sync/android/src/main/kotlin/"
    "app/wardpulse/watchsync/WatchPublication.kt"
)
CONSTANTS = ("NaN", "Infinity", "-Infinity")


class ArrayConstraintTests(unittest.TestCase):
    def test_recovery_requirements_enforce_nonempty_unique_ids(self):
        schemas = validator.load_schemas()
        owner = "dashboard_snapshot.schema.json"
        schema = schemas[owner]["$defs"]["recoveryRequirements"]
        self.assertEqual(validator.check_keywords(owner, schema), [])
        for ids, diagnostic in (
            ([], "minItems"),
            (["session", "session"], "uniqueItems"),
            (["session", "weekly"], None),
        ):
            with self.subTest(ids=ids):
                errors = validator.check(
                    {"allowanceIds": ids, "complete": True},
                    schema, schemas, owner, "requirements",
                )
                if diagnostic is None:
                    self.assertEqual(errors, [])
                else:
                    self.assertIn(diagnostic, "\n".join(errors))

    def test_unique_items_uses_json_equality(self):
        schema = {"type": "array", "uniqueItems": True}
        for value, duplicate in (
            ([True, 1], False),
            ([1, 1.0], True),
            ([{"a": [True]}, {"a": [1]}], False),
            ([{"a": [1], "b": 2}, {"b": 2.0, "a": [1.0]}], True),
        ):
            with self.subTest(value=value):
                errors = validator.check(value, schema, {}, "array", "items")
                self.assertEqual(bool(errors), duplicate)
        self.assertEqual(
            validator.check([1, 1], {"uniqueItems": False}, {}, "array", "items"),
            [],
        )


class ScratchValidatorCase(unittest.TestCase):
    """Owned external inputs for the actual validator; see FixtureValidatorTests."""

    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="wardpulse-fixture-test-")

        def cleanup():
            try:
                scratch.cleanup()
            finally:
                print("fixture-validator-scratch " + json.dumps({
                    "case": self.id(), "root": scratch.name,
                    "exists": Path(scratch.name).exists(),
                }, sort_keys=True), flush=True)

        self.addCleanup(cleanup)
        print("fixture-validator-scratch " + json.dumps({
            "case": self.id(), "root": scratch.name, "exists": True,
        }, sort_keys=True), flush=True)
        self.root = Path(scratch.name).resolve()
        self.assertFalse(self.root.is_relative_to(SOURCE), "test inputs must be outside Source")
        self.addCleanup(setattr, validator, "ROOT", validator.ROOT)
        self.addCleanup(setattr, validator, "FIXTURE_SCHEMAS", validator.FIXTURE_SCHEMAS)
        validator.ROOT = self.root
        validator.FIXTURE_SCHEMAS = {SUMMARY: validator.FIXTURE_SCHEMAS[SUMMARY]}

        for relative in (
            f"fixtures/{SUMMARY}",
            f"schemas/{SCHEMA}",
            f"schemas/{ORDERED_SCHEMA}",
            "schemas/dashboard_snapshot.schema.json",
            "schemas/budget_state.schema.json",
        ):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SOURCE / relative, target)
        self.summary_path = self.root / "fixtures" / SUMMARY
        self.sample = self.summary_path.read_bytes()
        self.schema_path = self.root / "schemas" / SCHEMA
        self.schema_sample = self.schema_path.read_bytes()
        self.legacy_version = json.loads(self.schema_sample)["properties"]["schemaVersion"]["const"]
        self.ordered_version = json.loads(
            (SOURCE / "schemas" / ORDERED_SCHEMA).read_bytes()
        )["properties"]["schemaVersion"]["const"]
        self.write_versions(self.legacy_version, self.ordered_version)

    def write_versions(self, legacy, ordered, native=None):
        # The legacy declarations come first, and the phone keeps a v9 literal,
        # so the pinned OLD module still reads only the v9 number. [native]
        # overrides the native sender's pair alone.
        self.write(
            WEAR_STORE,
            f"const val LEGACY_SCHEMA_VERSION = {legacy}\nconst val SCHEMA_VERSION = {ordered}\n",
        )
        native_legacy, native_ordered = native or (legacy, ordered)
        self.write(
            NATIVE_SENDER,
            f"internal const val LEGACY_SCHEMA_VERSION = {native_legacy}\n"
            f"internal const val SCHEMA_VERSION = {native_ordered}\n",
        )
        self.write(
            PHONE_SENDER,
            f"const legacyWatchSummarySchemaVersion = {legacy};\n"
            f"const watchSummarySchemaVersion = {ordered};\n"
            f"final summary = {{'schemaVersion': {legacy}}};\n",
        )

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def summary_value(self, fields, value, *, raw=False):
        summary = json.loads(self.sample)
        node = summary
        for field in fields[:-1]:
            node = node[field]
        marker = "__raw_json_token__"
        node[fields[-1]] = marker if raw else value
        text = json.dumps(summary, allow_nan=False)
        if raw:
            self.assertEqual(text.count(json.dumps(marker)), 1)
            text = text.replace(json.dumps(marker), value)
        self.summary_path.write_text(text, encoding="utf-8")

    def record_inputs(self, case):
        files = {}
        for path in sorted(self.root.rglob("*")):
            if path.is_dir():
                continue
            self.assertTrue(stat.S_ISREG(path.lstat().st_mode), "inputs must be regular files")
            content = path.read_bytes()
            files[path.relative_to(self.root).as_posix()] = {
                "sha256": hashlib.sha256(content).hexdigest(), "size": len(content),
            }
        identity = f"{self.id()}/{case}"
        print("fixture-validator-inputs " + json.dumps({"case": identity, "files": files}, sort_keys=True), flush=True)
        return identity

    def run_main(self, case):
        identity = self.record_inputs(case)
        output = io.StringIO()
        with redirect_stdout(output):
            result = validator.main()
        diagnostics = output.getvalue()
        print("fixture-validator-result " + json.dumps({
            "case": identity, "status": result, "diagnostics": diagnostics.splitlines(),
        }, sort_keys=True), flush=True)
        return result, diagnostics

    def assert_valid(self, case):
        result, output = self.run_main(case)
        self.assertEqual(result, 0, output)
        self.assertIn("1 against schemas", output)

    def assert_invalid(self, case, *diagnostics):
        result, output = self.run_main(case)
        self.assertEqual(result, 1, f"expected rejection for {case}: {output}")
        for diagnostic in diagnostics:
            self.assertIn(diagnostic, output)



class FixtureValidatorTests(ScratchValidatorCase):
    def test_mapped_summary_rejects_raw_constants(self):
        for token in CONSTANTS:
            with self.subTest(token=token):
                self.summary_value(("today", "usedPercent"), token, raw=True)
                self.assert_invalid(token, f"fixtures/{SUMMARY}", "invalid JSON constant", token)

    def test_mapped_read_independently_rejects_raw_constants(self):
        original_glob = Path.glob

        def without_syntax_entry(path, pattern, **kwargs):
            # Bypass only this file's first enumeration, never its bytes or decoder.
            return (
                entry for entry in original_glob(path, pattern, **kwargs)
                if not (path == self.root and pattern == "fixtures/**/*.json"
                        and entry == self.summary_path)
            )

        for token in CONSTANTS:
            with self.subTest(token=token):
                self.summary_value(("today", "usedPercent"), token, raw=True)
                with patch.object(Path, "glob", without_syntax_entry):
                    self.assert_invalid(token, f"fixtures/{SUMMARY}", "invalid JSON constant", token)

    def test_schema_loading_independently_rejects_raw_constants(self):
        for token in CONSTANTS:
            with self.subTest(token=token):
                schema = json.loads(self.schema_sample)
                schema["description"] = "__raw_json_token__"
                text = json.dumps(schema).replace('"__raw_json_token__"', token)
                self.schema_path.write_text(text, encoding="utf-8")
                identity = self.record_inputs(token)
                try:
                    validator.load_schemas()
                except ValueError as failure:
                    diagnostic = str(failure)
                else:
                    diagnostic = ""
                print("fixture-validator-result " + json.dumps({
                    "case": identity, "status": 1 if diagnostic else 0,
                    "diagnostics": [diagnostic] if diagnostic else [],
                }, sort_keys=True), flush=True)
                self.assertIn(f"schemas/{SCHEMA}", diagnostic)
                self.assertIn("invalid JSON constant", diagnostic)
                self.assertIn(token, diagnostic)

    def test_provider_syntax_rejects_raw_constants(self):
        relative = "fixtures/providers/mock/report.json"
        for token in CONSTANTS:
            with self.subTest(token=token):
                self.write(relative, '{"value": ' + token + '}')
                self.assert_invalid(token, relative, "invalid JSON constant", token)

    def test_quoted_constants_and_provider_syntax_only(self):
        for token in CONSTANTS:
            with self.subTest(token=token):
                self.summary_value(("alerts",), [{"severity": "info", "message": token}])
                self.write("fixtures/providers/mock/report.json", json.dumps({
                    "unmapped": token, "generatedAt": "2026-06-27", "other": [None, 0, True],
                }))
                self.assert_valid(token)

    def test_finite_null_and_zero_numbers(self):
        for token in ("0", "0.0", "12.5", "1e2", "null"):
            with self.subTest(token=token):
                self.summary_value(("today", "usedPercent"), token, raw=True)
                self.assert_valid(token)

    def test_boolean_and_quoted_tokens_are_not_numbers(self):
        for token in ("true", "false", '"NaN"', '"Infinity"', '"-Infinity"'):
            with self.subTest(token=token):
                self.summary_value(("today", "usedPercent"), token, raw=True)
                self.assert_invalid(token, f"{SUMMARY}.today.usedPercent", "expected number/null")

    def test_integer_fields_reject_floats_and_booleans(self):
        for token in ("1240.0", "true"):
            with self.subTest(token=token):
                self.summary_value(("today", "spent", "minorUnits"), token, raw=True)
                self.assert_invalid(token, f"{SUMMARY}.today.spent", "expected integer")
        for token in ("1240", "0"):
            with self.subTest(token=token):
                self.summary_value(("today", "spent", "minorUnits"), token, raw=True)
                self.assert_valid(token)

    def test_date_time_requires_a_timezone_aware_instant(self):
        for value in ("2026-06-27", "2026-06-27T18:42:00", "2026-06-27T18:42:00.123"):
            with self.subTest(value=value):
                self.summary_value(("generatedAt",), value)
                self.assert_invalid(value, f"{SUMMARY}.generatedAt", "timezone-aware date-time")

    def test_invalid_date_time_retains_field_diagnostics(self):
        self.summary_value(("generatedAt",), "2026-02-30T18:42:00Z")
        self.assert_invalid("invalid date", f"{SUMMARY}.generatedAt", "date-time")

    def test_utc_offset_and_fraction_instants(self):
        for value in (
            "2026-06-27T18:42:00Z",
            "2026-06-27T18:42:00+00:00",
            "2026-06-27T18:42:00+05:30",
            "2026-06-27T18:42:00-07:00",
            "2026-06-27T18:42:00.123456Z",
            "2026-06-27T18:42:00.123456+05:30",
        ):
            with self.subTest(value=value):
                self.summary_value(("generatedAt",), value)
                self.assert_valid(value)

    def test_date_format_is_separate_from_date_time(self):
        schema = json.loads(self.schema_sample)
        schema["properties"]["generatedAt"]["format"] = "date"
        self.schema_path.write_text(json.dumps(schema), encoding="utf-8")
        self.summary_value(("generatedAt",), "2026-06-27")
        self.assert_valid("date annotation")

    def test_malformed_json_has_file_diagnostics(self):
        relative = "fixtures/providers/mock/report.json"
        self.write(relative, '{"value": }')
        self.assert_invalid("malformed JSON", relative, "Expecting value")

    def test_schema_mapping_and_version_guards_remain_active(self):
        self.write("fixtures/snapshots/unmapped.json", "{}")
        self.assert_invalid("unmapped snapshot", "snapshots/unmapped.json", "not listed in FIXTURE_SCHEMAS")
        (self.root / "fixtures/snapshots/unmapped.json").unlink()

        schema = json.loads(self.schema_sample)
        schema["$defs"] = {"unused": {"unsupportedRule": True}}
        self.schema_path.write_text(json.dumps(schema), encoding="utf-8")
        self.assert_invalid("unused schema keyword", f"{SCHEMA}/$defs/unused", "unsupported keywords")
        self.schema_path.write_bytes(self.schema_sample)

        self.write_versions(0, self.ordered_version)
        self.assert_invalid("shell version mismatch", PHONE_SENDER, "schema version 0, contract says")


class OrderedSummaryContractTests(ScratchValidatorCase):
    """The v10 contract beside the retained v9 projection. OLD predates both guards."""

    def setUp(self):
        super().setUp()
        validator.FIXTURE_SCHEMAS = {
            SUMMARY: validator.FIXTURE_SCHEMAS[SUMMARY],
            ORDERED: ORDERED_SCHEMA,
        }
        self.ordered_path = self.root / "fixtures" / ORDERED
        shutil.copyfile(SOURCE / "fixtures" / ORDERED, self.ordered_path)
        self.ordered_sample = self.ordered_path.read_bytes()

    def ordered_value(self, field, value, *, remove=False):
        summary = json.loads(self.ordered_sample)
        if remove:
            del summary[field]
        else:
            summary[field] = value
        self.ordered_path.write_text(json.dumps(summary), encoding="utf-8")

    def assert_valid(self, case):
        result, output = self.run_main(case)
        self.assertEqual(result, 0, output)
        self.assertIn("2 against schemas", output)

    def test_ordered_example_is_mapped_and_valid(self):
        self.assertEqual(validator.FIXTURE_SCHEMAS[ORDERED], ORDERED_SCHEMA)
        self.assertIn(ORDERED, SOURCE_FIXTURE_SCHEMAS)
        self.assert_valid("ordered example")
        for mode in ("live", "demo", "mock"):
            with self.subTest(mode=mode):
                self.ordered_value("dataMode", mode)
                self.assert_valid(mode)

    def test_ordered_contract_is_strict(self):
        for field, value, diagnostic in (
            ("schemaVersion", 9, "expected 10"),
            ("dataMode", "unknown", "is not one of"),
            ("installId", "install-1", "does not match"),
            ("installId", "00000000-0000-4000-8000-00000000000A", "does not match"),
            ("generation", -1, "below minimum"),
            ("generation", 1.0, "expected integer"),
            ("sequence", 0, "below minimum"),
            ("sequence", True, "expected integer"),
            ("payload", "{}", "unexpected property 'payload'"),
        ):
            with self.subTest(field=field, value=value):
                self.ordered_value(field, value)
                self.assert_invalid(f"{field}={value!r}", f"{ORDERED}", diagnostic)
        for field in ("installId", "generation", "sequence"):
            with self.subTest(missing=field):
                self.ordered_value(field, None, remove=True)
                self.assert_invalid(f"missing {field}", f"missing required '{field}'")

    def test_ordered_body_follows_the_v9_contract(self):
        self.ordered_value("today", {"period": "week"})
        self.assert_invalid("ordered body", f"{ORDERED}.today")

    def test_legacy_projection_keeps_live_and_mock_only(self):
        self.summary_value(("dataMode",), "demo")
        self.assert_invalid("legacy demo", f"{SUMMARY}.dataMode", "is not one of")

    def test_ordered_mapping_guard_remains_active(self):
        validator.FIXTURE_SCHEMAS = {SUMMARY: validator.FIXTURE_SCHEMAS[SUMMARY]}
        self.assert_invalid("unmapped ordered example", ORDERED, "not listed in FIXTURE_SCHEMAS")

    def test_each_shell_declares_both_versions(self):
        for legacy, ordered, relative, diagnostic in (
            (self.legacy_version, self.legacy_version, WEAR_STORE, ORDERED_SCHEMA),
            (self.ordered_version, self.ordered_version, PHONE_SENDER, SCHEMA),
        ):
            with self.subTest(legacy=legacy, ordered=ordered):
                self.write_versions(legacy, ordered)
                self.assert_invalid("swapped versions", relative, "contract says", diagnostic)
        self.write_versions(self.legacy_version, self.ordered_version)
        self.write(WEAR_STORE, f"const val LEGACY_SCHEMA_VERSION = {self.legacy_version}\n")
        self.assert_invalid("missing ordered version", WEAR_STORE, "no schema version found")

    def test_native_sender_versions_are_guarded(self):
        # The native sender's empty replacement drifts alone; Dart and Wear stay correct.
        for native, diagnostic in (
            ((self.legacy_version + 1, self.ordered_version), SCHEMA),
            ((self.legacy_version, self.ordered_version + 1), ORDERED_SCHEMA),
        ):
            with self.subTest(native=native):
                self.write_versions(self.legacy_version, self.ordered_version, native)
                self.assert_invalid("native sender drift", NATIVE_SENDER, "contract says", diagnostic)
        self.write_versions(self.legacy_version, self.ordered_version)
        self.write(NATIVE_SENDER, f"internal const val SCHEMA_VERSION = {self.ordered_version}\n")
        self.assert_invalid("missing native legacy version", NATIVE_SENDER, "no schema version found")

    def test_missing_ordered_contract_is_reported(self):
        # The example and its mapping stay in place, as in production.
        (self.root / "schemas" / ORDERED_SCHEMA).unlink()
        self.assert_invalid("missing ordered contract", f"schemas/{ORDERED_SCHEMA}: missing")
        self.assert_invalid("missing mapped contract", ORDERED, f"schema {ORDERED_SCHEMA} is missing")

    def test_missing_legacy_contract_is_reported_through_ordered_references(self):
        # Both mappings and both examples stay in place; v10 reaches v9 by `$ref`.
        (self.root / "schemas" / SCHEMA).unlink()
        self.assert_invalid(
            "missing legacy contract",
            f"schemas/{SCHEMA}: missing",
            f"{SUMMARY}: schema {SCHEMA} is missing",
            f"{ORDERED}",
            f"names missing schema {SCHEMA}",
        )


if __name__ == "__main__":
    unittest.main()
