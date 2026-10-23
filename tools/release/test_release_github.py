"""HOST-only publication contracts with injected, offline GitHub responses."""

from copy import deepcopy
import hashlib
import itertools
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.parse

import release_github as release


SHA = "a" * 40
TAG = "v0.1.0"
NOTES = '### Minor Changes\n\n- Keep `$value` and $(command) literal.'


class FakeGitHub:
    def __init__(self):
        self.release, self.ref = None, None
        self.assets, self.unrelated, self.calls = [], [], []
        self.annotations = {}
        self.create_ref = True
        self.after = lambda path, method, result: None

    def __call__(self, path, method="GET", payload=None, missing=False, upload=None):
        self.calls.append((path, method, deepcopy(payload)))
        url = urllib.parse.urlsplit(path)
        query = urllib.parse.parse_qs(url.query)
        if url.path == "/releases" and method == "POST":
            self.release = {key: value for key, value in payload.items() if key != "make_latest"}
            self.release["id"] = 31
            result = self.release
        elif url.path == "/releases/31" and method == "PATCH":
            self.release.update({key: value for key, value in payload.items() if key != "make_latest"})
            # Model the observed omitted-tag reset; the public-transition risk is inferred.
            self.release["tag_name"] = payload.get("tag_name", "untagged-default")
            if self.create_ref:
                self.ref = {"ref": "refs/tags/" + TAG, "object": {"type": "commit", "sha": SHA}}
            result = self.release
        elif url.path == "/releases/31/assets" and method == "POST":
            data = upload[0].read()
            result = {"id": 100 + len(self.assets), "name": query["name"][0], "state": "uploaded",
                      "size": len(data), "digest": "sha256:" + hashlib.sha256(data).hexdigest()}
            self.assets.append(result)
        elif url.path in ("/releases", "/releases/31/assets"):
            items = self.unrelated + ([self.release] if self.release else []) if url.path == "/releases" else self.assets
            offset = (int(query["page"][0]) - 1) * 100
            result = items[offset:offset + 100]
        elif url.path == "/releases/31":
            result = self.release
        elif url.path == "/git/ref/tags/" + TAG:
            result = self.ref
        elif url.path.startswith("/git/tags/"):
            result = self.annotations[url.path.rsplit("/", 1)[1]]
        else:
            raise AssertionError((path, method))
        result = deepcopy(result)
        self.after(path, method, result)
        return result


class PublicationTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="wardpulse-publisher-test-")
        self.addCleanup(scratch.cleanup)
        self.directory = Path(scratch.name)
        self.manifest = {}
        for name in [f"binary-{index}.apk" for index in range(7)] + ["SHA256SUMS", "provenance.json"]:
            data = (name + "\n").encode()
            (self.directory / name).write_bytes(data)
            self.manifest[name] = {"size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        self.api = FakeGitHub()

    def publisher(self, draft="false", prerelease="false", latest="false"):
        return release.Publisher(self.api, SHA, TAG, NOTES, self.manifest, self.directory, draft, prerelease, latest)

    def mutations(self):
        return [call for call in self.api.calls if call[1] != "GET"]

    def test_all_state_options_stage_before_transition_and_observe_real_fields(self):
        for draft, prerelease, latest in itertools.product(("true", "false"), ("true", "false"), ("true", "false", "automatic")):
            with self.subTest(draft=draft, prerelease=prerelease, latest=latest):
                self.api = FakeGitHub()
                if latest == "true" and (draft == "true" or prerelease == "true"):
                    with self.assertRaisesRegex(ValueError, "latest=true"):
                        self.publisher(draft, prerelease, latest)
                    self.assertEqual(self.api.calls, [])
                    continue
                self.assertEqual(self.publisher(draft, prerelease, latest).publish(), 31)
                effects = self.mutations()
                creation = effects[0][2]
                self.assertEqual(creation, {"tag_name": TAG, "target_commitish": SHA, "name": TAG,
                                           "body": NOTES, "draft": True, "prerelease": prerelease == "true", "make_latest": "false"})
                uploads = [call for call in effects if "assets?name=" in call[0]]
                self.assertEqual(len(uploads), 9)
                if draft == "true":
                    self.assertEqual(len(effects), 10)
                    self.assertIsNone(self.api.ref)
                else:
                    self.assertEqual(effects[-1][0:2], ("/releases/31", "PATCH"))
                    policy = "legacy" if latest == "automatic" and prerelease == "false" else "false" if latest == "automatic" else latest
                    self.assertEqual(effects[-1][2], {"tag_name": TAG, "target_commitish": SHA, "name": TAG,
                                                    "body": NOTES, "draft": False,
                                                    "prerelease": prerelease == "true", "make_latest": policy})
                    before_patch = self.api.calls[:self.api.calls.index(effects[-1])]
                    self.assertTrue(any(path.startswith("/releases/31/assets?") and method == "GET" for path, method, _ in before_patch))
                    after_patch = self.api.calls[self.api.calls.index(effects[-1]) + 1:]
                    self.assertIn(("/releases/31", "GET", None), after_patch)
                self.assertEqual(self.api.release["id"], 31)
                self.assertEqual(self.api.release["tag_name"], TAG)
                self.assertEqual(self.api.release["name"], TAG)
                self.assertEqual(self.api.release["target_commitish"], SHA)
                self.assertIs(self.api.release["draft"], draft == "true")
                self.assertIs(self.api.release["prerelease"], prerelease == "true")
                self.assertEqual(self.api.release["body"], NOTES)
                self.assertNotIn("make_latest", self.api.release)

    def test_invalid_options_fail_before_checkout_notes_or_api(self):
        for flags in (("true", "false", "true"), ("false", "true", "true"), ("yes", "false", "false"), ("false", "false", "legacy")):
            env = dict(zip(("RELEASE_DRAFT", "RELEASE_PRERELEASE", "RELEASE_LATEST"), flags))
            with self.subTest(flags=flags), patch.dict(release.os.environ, env, clear=True), patch.object(release, "readiness") as ready, patch.object(release, "GitHub") as api, patch.object(release.subprocess, "check_output") as git:
                with self.assertRaisesRegex(SystemExit, "preserve all"):
                    release.main()
                ready.assert_not_called()
                api.assert_not_called()
                git.assert_not_called()

    def test_preexisting_releases_include_paginated_drafts_and_public_conflicts(self):
        for draft, prerelease in itertools.product((True, False), repeat=2):
            self.api = FakeGitHub()
            self.api.unrelated = [{"id": index + 1000, "tag_name": "other"} for index in range(100)]
            self.api.release = {"id": 31, "tag_name": TAG, "draft": draft, "prerelease": prerelease}
            with self.subTest(draft=draft, prerelease=prerelease), self.assertRaises(ValueError):
                self.publisher().publish()
            self.assertEqual(self.mutations(), [])
            self.assertIn(("/releases?per_page=100&page=2", "GET", None), self.api.calls)

    def test_conflict_appearing_at_repeated_check_refuses_creation(self):
        def appear(path, method, result):
            if path == "/releases?per_page=100&page=1":
                self.api.release = {"id": 31, "tag_name": TAG}
        self.api.after = appear
        with self.assertRaises(ValueError):
            self.publisher().publish()
        self.assertEqual(self.mutations(), [])

    def test_annotated_tags_peel_and_bad_or_cyclic_tags_fail_before_mutation(self):
        annotation = "b" * 40
        self.api.ref = {"ref": "refs/tags/" + TAG, "object": {"type": "tag", "sha": annotation}}
        self.api.annotations[annotation] = {"sha": annotation, "object": {"type": "commit", "sha": SHA}}
        self.publisher(draft="true").publish()
        for ref, obj in (("refs/tags/wrong", {"type": "commit", "sha": SHA}),
                         ("refs/tags/" + TAG, {"type": "commit", "sha": "c" * 40}),
                         ("refs/tags/" + TAG, {"type": "tag", "sha": annotation})):
            self.api = FakeGitHub()
            self.api.ref = {"ref": ref, "object": obj}
            self.api.annotations[annotation] = {"sha": annotation, "object": obj}
            with self.subTest(ref=ref, obj=obj), self.assertRaises(ValueError):
                self.publisher().publish()
            self.assertEqual(self.mutations(), [])

    def test_missing_public_tag_fails_and_preserves_published_state(self):
        self.api.create_ref = False
        with self.assertRaises(ValueError):
            self.publisher().publish()
        self.assertIs(self.api.release["draft"], False)
        self.assertEqual(len(self.api.assets), 9)
        self.assertEqual(self.mutations()[-1][1], "PATCH")

    def test_final_observation_refuses_changed_body_markers_or_identity(self):
        for key, value in (("body", "changed"), ("tag_name", "untagged-default"), ("name", "changed"),
                           ("draft", True), ("prerelease", True),
                           ("target_commitish", "c" * 40), ("id", 32)):
            self.api = FakeGitHub()
            def corrupt(path, method, result):
                if path == "/releases/31" and method == "GET" and self.api.release["draft"] is False:
                    result[key] = value
            self.api.after = corrupt
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.publisher().publish()
            self.assertIs(self.api.release["draft"], False)
            self.assertEqual(self.mutations()[-1][1], "PATCH")

    def test_creation_binding_checks_exact_notes_markers_and_identity(self):
        for key, value in (("body", "other"), ("prerelease", True), ("draft", False), ("target_commitish", "c" * 40), ("tag_name", "v0.1.1"), ("id", True)):
            self.api = FakeGitHub()
            def corrupt(path, method, result):
                if path == "/releases" and method == "POST":
                    result[key] = value
            self.api.after = corrupt
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.publisher().publish()
            self.assertEqual(len(self.mutations()), 1)

    def test_fresh_observation_detects_metadata_or_tag_mutation_after_upload(self):
        for change in ("body", "tag"):
            self.api = FakeGitHub()
            def mutate(path, method, result):
                if len(self.api.assets) == 9 and method == "POST":
                    if change == "body":
                        self.api.release["body"] = "changed"
                    else:
                        self.api.ref = {"ref": "refs/tags/" + TAG, "object": {"type": "commit", "sha": "c" * 40}}
            self.api.after = mutate
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.publisher().publish()
            self.assertFalse(any(method == "PATCH" for _, method, _ in self.mutations()))

    def test_all_asset_names_ids_sizes_states_and_optional_digests_gate_transition(self):
        for field, value in (("name", "unexpected.apk"), ("id", 999), ("size", 1), ("state", "new"), ("digest", "sha256:" + "f" * 64), ("missing", None), ("duplicate", None)):
            self.api = FakeGitHub()
            def corrupt(path, method, result):
                if path.startswith("/releases/31/assets?") and method == "GET":
                    if field == "missing":
                        result.pop()
                    elif field == "duplicate":
                        result[-1] = result[0]
                    else:
                        result[0][field] = value
            self.api.after = corrupt
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.publisher().publish()
            self.assertFalse(any(method == "PATCH" for _, method, _ in self.mutations()))
        self.api = FakeGitHub()
        self.api.after = lambda path, method, result: result.pop("digest", None) if type(result) is dict else None
        self.publisher().publish()  # GitHub may omit optional digests.

    def test_local_corruption_or_symlink_is_never_uploaded(self):
        name = sorted(self.manifest)[0]
        path = self.directory / name
        original = path.read_bytes()
        for symlink in (False, True):
            self.api = FakeGitHub()
            path.unlink()
            if symlink:
                target = self.directory / "target"
                target.write_bytes(original)
                path.symlink_to(target)
            else:
                path.write_bytes(b"corrupt")
            with self.subTest(symlink=symlink), self.assertRaises(ValueError):
                self.publisher().publish()
            self.assertEqual(len(self.mutations()), 1)

    def test_uncertain_create_upload_and_transition_effects_are_never_retried_or_erased(self):
        for stage in ("create", "upload", "transition"):
            self.api = FakeGitHub()
            def uncertain(path, method, result):
                if ((stage == "create" and path == "/releases" and method == "POST")
                        or (stage == "upload" and "assets?name=" in path and method == "POST")
                        or (stage == "transition" and method == "PATCH")):
                    raise OSError("Outcome unknown")
            self.api.after = uncertain
            with self.subTest(stage=stage), self.assertRaises(OSError):
                self.publisher().publish()
            effects = self.mutations()
            self.assertIsNotNone(self.api.release)
            self.assertEqual(sum(path == "/releases" and method == "POST" for path, method, _ in effects), 1)
            self.assertEqual(len(self.api.assets), {"create": 0, "upload": 1, "transition": 9}[stage])
            self.assertIs(self.api.release["draft"], stage != "transition")
            self.assertTrue(all(method in ("POST", "PATCH") for _, method, _ in effects))
            self.assertEqual(len(effects), {"create": 1, "upload": 2, "transition": 11}[stage])


if __name__ == "__main__":
    unittest.main()
