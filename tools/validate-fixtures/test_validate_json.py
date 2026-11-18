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

SUMMARY = "snapshots/watch_dashboard_summary.json"
SCHEMA = "watch_dashboard_summary.schema.json"
CONSTANTS = ("NaN", "Infinity", "-Infinity")


class FixtureValidatorTests(unittest.TestCase):
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
        version = json.loads(self.schema_sample)["properties"]["schemaVersion"]["const"]
        self.write(
            "apps/wear_android/app/src/main/java/app/wardpulse/wear/data/WatchSummaryStore.kt",
            f"const val SCHEMA_VERSION = {version}\n",
        )
        self.write(
            "apps/phone_flutter/lib/sync/watch_sync_service.dart",
            f"final summary = {{'schemaVersion': {version}}};\n",
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

        relative = "apps/phone_flutter/lib/sync/watch_sync_service.dart"
        self.write(relative, "final summary = {'schemaVersion': 0};\n")
        self.assert_invalid("shell version mismatch", relative, "schema version 0, contract says")


if __name__ == "__main__":
    unittest.main()
