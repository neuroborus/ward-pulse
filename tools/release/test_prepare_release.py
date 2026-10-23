"""HOST-only bridge contracts and isolated, pinned stock-CLI integration."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import prepare_release as release


REPO = Path(__file__).resolve().parents[2]
INTEGRITY = "sha512-L1i67bMfkK6iC/kDejuNO4pFgTRcWIObsD6Qof2woP1I4M8tj17DGlcpRaTzTv1DYSP5EMwWdEtR8X0Pj5Jg3Q=="
PUSH = '''val pushVersionCode = providers.gradleProperty("wardpulsePushVersionCode").map { value ->
    value.toIntOrNull()?.takeIf { it > 0 }
        ?: throw GradleException("wardpulsePushVersionCode must be a positive integer.")
}.orElse(1)
'''


def plan(current="0.1.0", target="0.1.1", package=release.PRODUCT, bump="patch"):
    return {"changesets": [{"id": "change", "summary": "Correct the summary display.",
                            "releases": [{"name": package, "type": bump}]}],
            "releases": [{"name": package, "type": bump, "oldVersion": current,
                          "newVersion": target, "changesets": ["change"]}]}


class ReleaseFixture(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="wardpulse-release-test-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.write("package.json", json.dumps({"name": "release-test", "private": True, "version": "0.0.0",
                                             "workspaces": ["docs/site", "tools/release"],
                                             "devDependencies": {"@changesets/cli": release.CLI_VERSION}}))
        self.write("docs/site/package.json", json.dumps({"name": "@wardpulse/docs", "private": True, "version": "0.0.0"}))
        self.write(".changeset/config.json", (REPO / ".changeset/config.json").read_text())
        self.write("tools/release/package.json", json.dumps({"name": release.PRODUCT, "private": True, "version": "0.1.0"}))
        self.write("tools/release/CHANGELOG.md", "# Product\n\n## 0.1.0\n\n### Minor Changes\n\n- Existing dashboard.\n")
        self.write(release.SOURCES["phone"], "name: phone\nversion: 0.1.0+1 # retained\n")
        for name, code in (("wear", "2"), ("legacy", "1"), ("push", "pushVersionCode.get()")):
            self.write(release.SOURCES[name], (PUSH if name == "push" else "") +
                       'android {\n    defaultConfig {\n        versionName = "0.1.0" // retained\n' +
                       f'        versionCode = {code}\n    }}\n}}\n')
        self.fragment("change", "patch", "Correct the summary display.")
        self.stock = Mock()
        self.stock.plan.return_value = plan()
        self.stock.version.side_effect = self.generate
        self.stock.reconcile_lock.side_effect = lambda: self.write("package-lock.json", json.dumps({
            "packages": {"tools/release": {"version": "0.1.1"}}}))

    def write(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content.encode("utf-8"))
        return path

    def fragment(self, name, bump, summary):
        return self.write(f".changeset/{name}.md", f'---\n"{release.PRODUCT}": {bump}\n---\n\n{summary}\n')

    def generate(self):
        self.write("tools/release/package.json", json.dumps({"name": release.PRODUCT, "private": True, "version": "0.1.1"}))
        self.write("tools/release/CHANGELOG.md", "# Product\n\n## 0.1.1\n\n### Patch Changes\n\n- Correct the summary display.\n")
        (self.root / ".changeset/change.md").unlink()

    def snapshot(self):
        return {str(path.relative_to(self.root)): path.read_bytes() for path in self.root.rglob("*") if path.is_file()}


class PreparationTests(ReleaseFixture):
    def refused(self, target="0.1.1"):
        before = self.snapshot()
        with self.assertRaises(ValueError):
            release.prepare(self.root, target, self.stock)
        self.stock.version.assert_not_called()
        self.stock.reconcile_lock.assert_not_called()
        self.assertEqual(before, self.snapshot())

    def test_fragment_ownership_is_checked_individually(self):
        for package, bump in (("@wardpulse/docs", "patch"), ("release-test", "none"), (release.PRODUCT, "none")):
            with self.subTest(package=package, bump=bump):
                proposed = plan()
                proposed["changesets"].append({"id": "foreign", "releases": [{"name": package, "type": bump}]})
                self.stock.plan.return_value = proposed
                self.refused()

    def test_official_plan_target_and_stable_selection(self):
        for target in ("0.0.9", "0.1.2", "v0.1.1", "0.1.1-beta.1", "01.1.1", "0.1.1+1", "0.1.1\n"):
            with self.subTest(target=target):
                self.refused(target)
        for key, value in (("preState", {"mode": "pre"}), ("releases", [])):
            proposed = plan()
            proposed[key] = value
            self.stock.plan.return_value = proposed
            self.refused()
        for key, value in (("oldVersion", "0.0.9"), ("name", "@wardpulse/docs")):
            proposed = plan()
            proposed["releases"][0][key] = value
            self.stock.plan.return_value = proposed
            self.refused()

    def test_unsafe_configuration_and_wrong_ledger_fail_before_generation(self):
        for relative, key, value in ((".changeset/config.json", "commit", True),
                                     ("tools/release/package.json", "private", False),
                                     ("tools/release/package.json", "version", "0.1.0-preview.1")):
            path = self.root / relative
            original = path.read_bytes()
            data = json.loads(original)
            data[key] = value
            path.write_text(json.dumps(data))
            with self.subTest(path=relative, key=key):
                self.refused()
            path.write_bytes(original)

    def test_native_declarations_and_allocations_fail_before_generation(self):
        mutations = [
            ("phone", "version: 0.1.0+1", "version: 0.1.1+1"),
            ("phone", "version: 0.1.0+1", "version: 0.1.0+0"),
            ("phone", "version: 0.1.0+1", "version: 0.1.0+01"),
            ("phone", "version: 0.1.0+1", "version: 0.1.0+1\nversion: 0.1.0+1"),
            ("wear", "versionCode = 2", "versionCode = 3"),
            ("wear", "versionCode = 2", "versionCode = 2147483648"),
            ("legacy", "versionCode = 1", "versionCode = 1 + 1"),
            ("legacy", "versionCode = 1", "versionCode = 1\n        versionCode = 2"),
            ("legacy", "versionCode = 1", "versionCode = 1\n        android.defaultConfig.versionCode = 2"),
            ("legacy", "versionCode = 1", "versionCode = 1\n        setVersionCode(2)"),
            ("legacy", 'versionName = "0.1.0"', 'versionName = project.version.toString()'),
            ("push", "pushVersionCode.get()", "2"),
            ("push", ".orElse(1)", ".orElse(0)"),
            ("push", "it > 0", "it >= 0"),
            ("legacy", 'versionName = "0.1.0"', 'versionName = "0.1.0"\n    }\n    buildTypes { versionName = "0.1.0"'),
        ]
        for name, old, new in mutations:
            path = self.root / release.SOURCES[name]
            original = path.read_text()
            with self.subTest(name=name, replacement=new):
                path.write_text(original.replace(old, new))
                self.refused()
            path.write_text(original)

    def test_quoted_duplicate_phone_versions_fail_before_generation(self):
        path = self.root / release.SOURCES["phone"]
        original = path.read_bytes()
        for key in ('"version"', "'version'"):
            with self.subTest(key=key):
                path.write_bytes(original + f"{key} : 0.1.0+9\n".encode("utf-8"))
                self.refused()
                self.stock.plan.assert_not_called()
            path.write_bytes(original)

    def test_future_code_overflow_is_preflighted_for_each_namespace(self):
        for name in ("phone", "legacy", "push"):
            originals = self.snapshot()
            if name == "phone":
                self.write(release.SOURCES["phone"], "version: 0.1.0+2147483645\n")
                path = self.root / release.SOURCES["wear"]
                path.write_text(path.read_text().replace("versionCode = 2", "versionCode = 2147483646"))
            else:
                path = self.root / release.SOURCES[name]
                path.write_text(path.read_text().replace("versionCode = 1", f"versionCode = {release.MAX_CODE}")
                                .replace("orElse(1)", f"orElse({release.MAX_CODE})"))
            with self.subTest(namespace=name):
                self.refused()
            for relative, data in originals.items():
                (self.root / relative).write_bytes(data)

    def test_maximum_valid_pair_and_independent_face_histories(self):
        self.write(release.SOURCES["phone"], "version: 0.1.0+2147483643\n")
        path = self.root / release.SOURCES["wear"]
        path.write_text(path.read_text().replace("versionCode = 2", "versionCode = 2147483644"))
        path = self.root / release.SOURCES["legacy"]
        path.write_text(path.read_text().replace("versionCode = 1", "versionCode = 9"))
        self.assertTrue(release.prepare(self.root, "0.1.1", self.stock))
        sources = release.native_state(self.root, "0.1.1")
        self.assertEqual({name: item.code for name, item in sources.items()},
                         {"phone": 2147483645, "wear": 2147483646, "legacy": 10, "push": 2})

    def test_transition_preserves_formatting_and_complete_repeat_is_noop(self):
        before = release.native_state(self.root, "0.1.0")
        path = before["wear"].path
        path.write_bytes(path.read_bytes().replace(b"\n", b"\r\n"))
        before = release.native_state(self.root, "0.1.0")
        self.assertTrue(release.prepare(self.root, "0.1.1", self.stock))
        for name, code in (("phone", 3), ("wear", 4), ("legacy", 2), ("push", 2)):
            self.assertEqual(before[name].path.read_bytes(), before[name].updated("0.1.1", code).encode())
        snapshot = self.snapshot()
        self.stock.reset_mock()
        self.assertFalse(release.prepare(self.root, "0.1.1", self.stock))
        self.assertEqual(snapshot, self.snapshot())
        self.stock.plan.assert_not_called()
        self.stock.version.assert_not_called()
        self.stock.reconcile_lock.assert_not_called()

        self.fragment("change", "minor", "Add a new summary view.")
        self.stock.plan.return_value = plan("0.1.1", "0.2.0", bump="minor")
        snapshot = self.snapshot()
        self.assertFalse(release.prepare(self.root, "0.1.1", self.stock))
        self.assertEqual(snapshot, self.snapshot())
        self.stock.plan.assert_called_once_with()
        self.stock.version.assert_not_called()
        self.stock.reconcile_lock.assert_not_called()

    def test_same_target_without_fragments_retains_preflight_guards(self):
        (self.root / ".changeset/change.md").unlink()
        for relative, old, new in (
                (".changeset/config.json", '"commit": false', '"commit": true'),
                ("package.json", release.CLI_VERSION, "3.0.2"),
                ("tools/release/package.json", '"private": true', '"private": false'),
                (release.SOURCES["wear"], "0.1.0", "0.1.1"),
                (release.SOURCES["wear"], "versionCode = 2", "versionCode = 4")):
            path = self.root / relative
            original = path.read_bytes()
            with self.subTest(path=relative, replacement=new):
                self.assertIn(old, original.decode("utf-8"))
                path.write_bytes(original.replace(old.encode(), new.encode()))
                self.refused("0.1.0")
                self.stock.plan.assert_not_called()
            path.write_bytes(original)
        for name in ("pre.json", "unexpected.json", ".hidden.md"):
            with self.subTest(input=name):
                path = self.write(".changeset/" + name, "unparsed input")
                self.refused("0.1.0")
                self.stock.plan.assert_not_called()
                path.unlink()
        directory = self.root / ".changeset/legacy"
        directory.mkdir()
        self.refused("0.1.0")
        self.stock.plan.assert_not_called()

    def test_same_target_pending_fragments_require_valid_official_ownership(self):
        foreign = plan()
        foreign["changesets"].append({"id": "foreign", "releases": [{"name": "release-test", "type": "none"}]})
        for proposed in (foreign, {**plan(), "preState": {"mode": "pre"}},
                         {**plan(), "changesets": None}, {**plan(), "changesets": [{}]},
                         {**plan(), "releases": []}):
            with self.subTest(plan=proposed):
                self.stock.plan.return_value = proposed
                self.refused("0.1.0")
        self.assertEqual(self.stock.plan.call_count, 5)

        error = subprocess.CalledProcessError(1, ["npm", "exec"])
        self.stock.plan.side_effect = error
        before = self.snapshot()
        with self.assertRaises(subprocess.CalledProcessError) as raised:
            release.prepare(self.root, "0.1.0", self.stock)
        self.assertIs(raised.exception, error)
        self.assertEqual(before, self.snapshot())
        self.stock.version.assert_not_called()
        self.stock.reconcile_lock.assert_not_called()

    def test_generation_and_lock_failures_preserve_partial_state(self):
        for stage in ("version", "reconcile_lock"):
            with self.subTest(stage=stage):
                self.stock.version.side_effect = self.generate
                getattr(self.stock, stage).side_effect = OSError("injected failure")
                with self.assertRaisesRegex(RuntimeError, "partial.*preserved"):
                    release.prepare(self.root, "0.1.1", self.stock)
                self.assertEqual(release.native(self.root, "phone").version, "0.1.0")
                if stage == "reconcile_lock":
                    self.assertEqual(release.ledger(self.root), "0.1.1")
                    self.assertFalse((self.root / ".changeset/change.md").exists())
                    with self.assertRaisesRegex(ValueError, "Mixed"):
                        release.prepare(self.root, "0.1.1", self.stock)

    def test_unconsumed_generation_does_not_reach_native_writes(self):
        def incomplete_generation():
            self.generate()
            self.fragment("change", "patch", "Correct the summary display.")

        self.stock.version.side_effect = incomplete_generation
        with self.assertRaisesRegex(RuntimeError, "unconsumed"):
            release.prepare(self.root, "0.1.1", self.stock)
        self.stock.reconcile_lock.assert_not_called()
        self.assertEqual(release.native(self.root, "phone").version, "0.1.0")

    def test_stale_workspace_lock_does_not_reach_native_writes(self):
        self.stock.reconcile_lock.side_effect = lambda: self.write("package-lock.json", json.dumps({
            "packages": {"tools/release": {"version": "0.1.0"}}}))
        with self.assertRaisesRegex(RuntimeError, "workspace lock"):
            release.prepare(self.root, "0.1.1", self.stock)
        self.assertEqual(release.ledger(self.root), "0.1.1")
        self.assertEqual(release.native(self.root, "phone").version, "0.1.0")

    def test_native_edits_during_generation_are_preserved(self):
        def generation_with_edit():
            self.generate()
            self.write(release.SOURCES["legacy"], "// Concurrent edit; reconcile manually.\n")

        self.stock.version.side_effect = generation_with_edit
        with self.assertRaisesRegex(RuntimeError, "Native source changed"):
            release.prepare(self.root, "0.1.1", self.stock)
        self.assertEqual(release.native(self.root, "phone").version, "0.1.0")
        self.assertEqual((self.root / release.SOURCES["legacy"]).read_text(), "// Concurrent edit; reconcile manually.\n")

    def test_partial_native_io_failure_is_preserved_and_refuses_retry(self):
        original = Path.write_bytes

        def write(path, data):
            if path == self.root / release.SOURCES["wear"]:
                raise OSError("injected native write failure")
            return original(path, data)

        with patch.object(Path, "write_bytes", write), self.assertRaisesRegex(RuntimeError, "partial"):
            release.prepare(self.root, "0.1.1", self.stock)
        self.assertEqual(release.native(self.root, "phone").code, 3)
        self.assertEqual(release.native(self.root, "wear").version, "0.1.0")
        with self.assertRaisesRegex(ValueError, "Mixed"):
            release.prepare(self.root, "0.1.1", self.stock)
        self.stock.version.assert_called_once()

    def test_notes_select_exact_version_and_preserve_literal_markdown(self):
        body = '### Patch Changes\n\n- Keep `$value`, $(command), and `backticks` literal.\n\n```md\n## 9.9.9\n```'
        self.write("tools/release/CHANGELOG.md", "# Product\n\n## 0.1.10\n\n- Other.\n\n## 0.1.1\n\n" + body + "\n\n## 0.1.0\n\n- Earlier.\n")
        self.assertEqual(release.release_notes(self.root, "0.1.1"), body)
        for text in ("## 0.1.10\n- Other.\n", "## 0.1.1\n\n### Patch Changes\n", "## 0.1.1\n- A.\n## 0.1.1\n- B.\n"):
            self.write("tools/release/CHANGELOG.md", text)
            with self.assertRaises(ValueError):
                release.release_notes(self.root, "0.1.1")


class ReadinessTests(ReleaseFixture):
    def setUp(self):
        super().setUp()
        (self.root / ".changeset/change.md").unlink()

    def test_prepared_notes_are_literal_and_read_only_without_stock(self):
        body = '### Minor Changes\n\n- Keep $(command), `$value`, and [links](https://example.invalid) literal.'
        self.write("tools/release/CHANGELOG.md", "# Product\n\n## 0.1.0\n\n" + body + "\n")
        before = self.snapshot()
        with patch.object(release.Stock, "run", side_effect=AssertionError("npm must not run")):
            ready = release.readiness(self.root, "v0.1.0")
        self.assertEqual(ready, {"version": "0.1.0", "codes": {"phone": 1, "wear": 2, "legacy": 1, "push": 1}, "notes": body})
        self.assertEqual(before, self.snapshot())

    def test_pending_or_pre_mode_inputs_fail_without_parsing_or_writes(self):
        for name in ("pending.md", "pre.json", "legacy-directory"):
            with self.subTest(name=name):
                path = self.write(".changeset/" + name, "unparsed input")
                before = self.snapshot()
                with self.assertRaisesRegex(ValueError, "Pending Changesets"):
                    release.readiness(self.root, "v0.1.0")
                self.assertEqual(before, self.snapshot())
                path.unlink()

    def test_tag_ledger_native_and_nonempty_exact_notes_must_agree(self):
        for tag in ("0.1.0", "v0.1.0-beta.1", "v0.1.1", "v01.1.0"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.readiness(self.root, tag)
        path = self.root / release.SOURCES["wear"]
        original = path.read_bytes()
        path.write_bytes(original.replace(b"0.1.0", b"0.1.1"))
        with self.assertRaisesRegex(ValueError, "Mixed"):
            release.readiness(self.root, "v0.1.0")
        path.write_bytes(original)
        for notes in ("## 0.1.1\n- Other.\n", "## 0.1.0\n\n### Minor Changes\n"):
            self.write("tools/release/CHANGELOG.md", notes)
            with self.assertRaisesRegex(ValueError, "notes"):
                release.readiness(self.root, "v0.1.0")
        (self.root / "tools/release/CHANGELOG.md").unlink()
        with self.assertRaises(FileNotFoundError):
            release.readiness(self.root, "v0.1.0")


class StockCommandTests(unittest.TestCase):
    def test_cache_override_and_npm_default_apply_to_cli_and_lock(self):
        root = Path("fixture")
        for cache in (None, Path("selected-cache")):
            with (self.subTest(cache=cache),
                  patch.dict(os.environ, {"npm_config_cache": "configured-cache"}),
                  patch.object(release.subprocess, "run") as run):
                stock = release.Stock(root, cache)
                stock.changeset("status")
                stock.reconcile_lock()
                self.assertEqual(run.call_count, 2)
                for call in run.call_args_list:
                    command = call.args[0]
                    self.assertIn("--offline", command)
                    self.assertIn("--ignore-scripts", command)
                    self.assertEqual([arg for arg in command if arg.startswith("--cache=")],
                                     [] if cache is None else ["--cache=selected-cache"])
                    self.assertEqual(call.kwargs, {"cwd": root, "check": True})
                self.assertIn(f"--package=@changesets/cli@{release.CLI_VERSION}", run.call_args_list[0].args[0])
                self.assertEqual(os.environ["npm_config_cache"], "configured-cache")


class StockIntegrationTests(ReleaseFixture):
    def test_pinned_bootstrap_lock_discovery_and_future_transition(self):
        stock = release.Stock(self.root)
        self.write("tools/release/package.json", json.dumps({"name": release.PRODUCT, "private": True, "version": "0.0.0"}))
        (self.root / "tools/release/CHANGELOG.md").unlink()
        (self.root / ".changeset/change.md").unlink()
        stock.run(["git", "init", "-b", "main"])
        stock.run(["git", "add", "."])
        stock.run(["git", "-c", "user.name=Release Test", "-c", "user.email=release@example.invalid", "commit", "-m", "Initial test data"])
        self.fragment("initial", "minor", "Record the existing candidate dashboard.")
        stock.reconcile_lock()
        lock = release.read_json(self.root / "package-lock.json")
        self.assertEqual(lock["packages"]["node_modules/@changesets/cli"]["version"], release.CLI_VERSION)
        self.assertEqual(lock["packages"]["node_modules/@changesets/cli"]["integrity"], INTEGRITY)
        self.assertEqual(release.validate_plan(stock.plan(), "0.0.0"), "0.1.0")
        stock.version()
        stock.reconcile_lock()
        self.assertEqual(release.ledger(self.root), "0.1.0")
        self.assertFalse((self.root / ".changeset/initial.md").exists())
        self.assertEqual((self.root / "tools/release/CHANGELOG.md").read_text(),
                         "# @wardpulse/app\n\n## 0.1.0\n\n### Minor Changes\n\n- Record the existing candidate dashboard.\n")
        self.assertEqual(release.read_json(self.root / "package-lock.json")["packages"]["tools/release"]["version"], "0.1.0")
        self.fragment("change", "patch", "Correct the summary display.")
        self.assertEqual(release.status(self.root, stock)["target"], "0.1.1")
        self.assertTrue(release.prepare(self.root, "0.1.1", stock))
        self.assertEqual({name: source.code for name, source in release.native_state(self.root, "0.1.1").items()},
                         {"phone": 3, "wear": 4, "legacy": 2, "push": 2})
        self.assertFalse((self.root / ".changeset/change.md").exists())
        before = self.snapshot()
        with (patch.object(stock, "plan", wraps=stock.plan) as planning,
              patch.object(stock, "version", wraps=stock.version) as generation,
              patch.object(stock, "reconcile_lock", wraps=stock.reconcile_lock) as locking):
            self.assertFalse(release.prepare(self.root, "0.1.1", stock))
            planning.assert_not_called()
            generation.assert_not_called()
            locking.assert_not_called()
        self.assertEqual(before, self.snapshot())
        self.fragment("pending", "patch", "Improve release preparation diagnostics.")
        self.assertEqual(release.status(self.root, stock)["target"], "0.1.2")
        before = self.snapshot()
        with (patch.object(stock, "plan", wraps=stock.plan) as planning,
              patch.object(stock, "version", wraps=stock.version) as generation,
              patch.object(stock, "reconcile_lock", wraps=stock.reconcile_lock) as locking):
            self.assertFalse(release.prepare(self.root, "0.1.1", stock))
            planning.assert_called_once_with()
            generation.assert_not_called()
            locking.assert_not_called()
        self.assertEqual(before, self.snapshot())
        self.write(".changeset/foreign.md", '---\n"@wardpulse/docs": patch\n---\n\nChange documentation.\n')
        before = self.snapshot()
        with (patch.object(stock, "plan", wraps=stock.plan) as planning,
              patch.object(stock, "version", wraps=stock.version) as generation,
              patch.object(stock, "reconcile_lock", wraps=stock.reconcile_lock) as locking):
            with self.assertRaisesRegex(ValueError, "must target only"):
                release.prepare(self.root, "0.1.1", stock)
            planning.assert_called_once_with()
            generation.assert_not_called()
            locking.assert_not_called()
        self.assertEqual(before, self.snapshot())
        for relative in ("package.json", "docs/site/package.json"):
            self.assertEqual(release.read_json(self.root / relative)["version"], "0.0.0")


if __name__ == "__main__":
    unittest.main()
