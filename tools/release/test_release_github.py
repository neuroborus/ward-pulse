"""HOST-only publication contracts with injected, offline GitHub responses."""

from copy import deepcopy
import hashlib
import http.client
from io import BytesIO, StringIO
import itertools
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import textwrap
import unittest
from unittest.mock import Mock, call, patch
import urllib.error
import urllib.parse
import zipfile

import release_github as release


SHA = "a" * 40
TAG = "v0.1.0"
NOTES = '### Minor Changes\n\n- Keep `$value` and $(command) literal.'
REPOSITORY_ID = "123"


class FakeGitHub:
    def __init__(self):
        self.release, self.ref = None, None
        self.assets, self.unrelated, self.calls = [], [], []
        self.annotations = {}
        self.create_ref = True
        self.after = lambda path, method, result: None

    def __call__(self, path, method="GET", payload=None, missing=False, upload=None, *,
                 on_response=None, page=None):
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
        if on_response is not None:
            on_response()
        if missing and result is None:
            return release.NOT_FOUND
        if page is not None:
            return result, {}
        return result


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.sleep = self.enterContext(patch.object(release, "sleep"))
        scratch = tempfile.TemporaryDirectory(prefix="wardpulse-publisher-test-")
        self.addCleanup(scratch.cleanup)
        self.directory = Path(scratch.name) / "transfer"
        self.directory.mkdir()
        self.manifest = {}
        for name in ["wardpulse-phone-0.1.0-code1.aab", "WardPulse-0.1.0-Android.apk",
                     "wardpulse-wear-0.1.0-code2.aab", "WardPulse-0.1.0-WearOS.apk",
                     "wardpulse-legacy-0.1.0-code1.aab", "WardPulse-0.1.0-WatchFace-WearOS5Plus.apk",
                     "wardpulse-push-0.1.0-code1.apk", "SHA256SUMS", "provenance.json"]:
            data = (name + "\n").encode()
            (self.directory / name).write_bytes(data)
            self.manifest[name] = {"size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        self.api = FakeGitHub()

    def publisher(self, draft="false", prerelease="false", latest="false", *, api=None):
        return release.Publisher(self.api if api is None else api, SHA, TAG, NOTES, self.manifest,
                                 self.directory, draft, prerelease, latest)

    def mutations(self):
        return [call for call in self.api.calls if call[1] != "GET"]

    def mock_http_operation(self, target, verb, *, after_creation=False):
        with patch.object(release.urllib.request, "build_opener") as build_opener:
            api = release.GitHub("synthetic-token", "example/project", REPOSITORY_ID)

        def request(path, method="GET", *args, **kwargs):
            if (path.partition("?")[0] != target or method != verb
                    or (after_creation and self.api.release is None)):
                return self.api(path, method, *args, **kwargs)
            # Apply the fake server effect, with status confirmation left to the real transport.
            fake_kwargs = kwargs.copy()
            fake_kwargs.pop("on_response", None)
            self.api(path, method, *args, **fake_kwargs)
            return api(path, method, *args, **kwargs)

        return request, build_opener.return_value.open

    def assert_cli_failure(self, detail, api=None):
        manifest = self.directory.parent / "verified-transfer.json"
        manifest.write_text(json.dumps(self.manifest))
        env = {
            "RELEASE_DRAFT": "false", "RELEASE_PRERELEASE": "false", "RELEASE_LATEST": "false",
            "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REF": "refs/heads/main",
            "SOURCE_SHA": SHA, "RELEASE_TAG": TAG, "RELEASE_VERSION": TAG[1:],
            "VERIFIED_TRANSFER": str(manifest), "TRANSFER_DIR": str(self.directory),
            "GH_TOKEN": "synthetic-token", "GITHUB_REPOSITORY": "example/project",
            "GITHUB_REPOSITORY_ID": REPOSITORY_ID,
        }
        with (
            patch.dict(release.os.environ, env, clear=True),
            patch.object(release, "readiness", return_value={"version": TAG[1:], "notes": NOTES}),
            patch.object(release, "GitHub", return_value=self.api if api is None else api) as github,
            patch.object(release.subprocess, "check_output", return_value=SHA + "\n"),
            patch("sys.stdout", new_callable=StringIO) as stdout,
            patch("sys.stderr", new_callable=StringIO) as stderr,
            self.assertRaises(SystemExit) as failure,
        ):
            release.main()
        github.assert_called_once_with("synthetic-token", "example/project", REPOSITORY_ID)
        self.assertEqual((stdout.getvalue(), stderr.getvalue()), ("", ""))
        self.assertEqual(
            str(failure.exception),
            "Publication failed; preserve all release/tag/asset state, including any partial or public "
            "release, for Owner reconciliation. Do not blindly retry.\n"
            f"Publication diagnostic {detail}",
        )

    def test_http_failures_report_only_stage_operation_and_status_and_preserve_effects(self):
        cases = (
            ("/releases", "POST", "draft-creation", "create-draft", 422, 0, True),
            ("/releases/31", "GET", "draft-observation", "read-release", 404, 0, True),
            ("/releases", "GET", "draft-observation", "list-releases", 503, 0, True),
            ("/git/ref/tags/" + TAG, "GET", "draft-observation", "read-tag-ref", 403, 0, True),
            ("/releases/31/assets", "POST", "asset-upload", "upload-asset", 502, 1, True),
            ("/releases/31/assets", "GET", "asset-verification", "list-release-assets", 503, 9, True),
            ("/releases/31", "PATCH", "publish-transition", "publish-release", 403, 9, False),
            ("/releases/31", "GET", "final-verification", "read-release", 500, 9, False),
        )
        for target, verb, stage, operation, status, asset_count, draft in cases:
            with self.subTest(stage=stage):
                self.api = FakeGitHub()
                failed_at = []

                def fail(path, method, result):
                    if (path.partition("?")[0] == target and method == verb
                            and self.api.release is not None and self.api.release["draft"] is draft):
                        failed_at.append(len(self.api.calls))
                        error = urllib.error.HTTPError(
                            "https://example.invalid" + path, status, "synthetic response text",
                            {"X-Test": "synthetic header value"}, BytesIO(b"synthetic response body"),
                        )
                        self.addCleanup(error.close)
                        raise error

                self.api.after = fail
                self.assert_cli_failure(f"stage={stage} operation={operation} http_status={status}")
                self.assertEqual(failed_at, [len(self.api.calls)])
                self.assertEqual(len(self.mutations()), 1 + asset_count + (0 if draft else 1))
                self.assertEqual(len(self.api.assets), asset_count)
                self.assertIs(self.api.release["draft"], draft)
                self.assertEqual(self.api.release["body"], NOTES)
                self.assertEqual(self.api.ref is None, draft)
                self.sleep.assert_not_called()

    def test_get_requests_require_cache_revalidation(self):
        with patch.object(release.urllib.request, "build_opener") as build_opener:
            api = release.GitHub("synthetic-token", "example/project", REPOSITORY_ID)
        open_response = build_opener.return_value.open
        response = open_response.return_value.__enter__.return_value
        response.read.return_value = b"{}"
        for method, path in (("GET", "/releases?per_page=100&page=1"), ("GET", "/releases/31"),
                             ("GET", "/git/ref/tags/" + TAG), ("POST", "/releases"), ("PATCH", "/releases/31")):
            with self.subTest(method=method, path=path):
                response.status = 201 if method == "POST" else 200
                api(path, method)
                request = open_response.call_args.args[0]
                self.assertEqual(request.get_header("Cache-control"), "no-cache" if method == "GET" else None)

    def test_unexpected_success_status_is_reported_before_body_is_read(self):
        api, open_response = self.mock_http_operation("/releases", "GET")
        response = open_response.return_value.__enter__.return_value
        response.status = 202
        self.assert_cli_failure("stage=preflight operation=list-releases http_status=202", api=api)
        response.read.assert_not_called()

    def test_mutation_response_body_failures_report_response_stage(self):
        cases = (
            ("/releases", "draft-creation-response", b"synthetic invalid JSON", "invalid-data", 0),
            ("/releases/31/assets", "asset-upload-response", b"\xff", "invalid-data", 1),
            ("/releases", "draft-creation-response", http.client.IncompleteRead(b"synthetic body"),
             "transport-error", 0),
            ("/releases/31/assets", "asset-upload-response", TimeoutError("synthetic timeout"), "io-error", 1),
        )
        for target, stage, body_or_error, category, asset_count in cases:
            with self.subTest(stage=stage, category=category):
                self.api = FakeGitHub()
                api, open_response = self.mock_http_operation(target, "POST")
                response = open_response.return_value.__enter__.return_value
                response.status = 201
                response.read.side_effect = [body_or_error]
                self.assert_cli_failure(f"stage={stage} category={category}", api=api)
                response.read.assert_called_once_with()
                self.assertEqual(len(self.mutations()), 1 + asset_count)
                self.assertEqual(len(self.api.assets), asset_count)
                self.assertIs(self.api.release["draft"], True)
                self.assertIsNone(self.api.ref)

    def test_upload_response_validation_failure_preserves_first_stored_asset(self):
        def corrupt(path, method, result):
            if path.startswith("/releases/31/assets?") and method == "POST":
                result["name"] = "unexpected.apk"

        self.api.after = corrupt
        self.assert_cli_failure("stage=asset-upload-response category=validation-failed")
        self.assertEqual(len(self.mutations()), 2)
        self.assertEqual([asset["name"] for asset in self.api.assets], [sorted(self.manifest)[0]])
        self.assertIs(self.api.release["draft"], True)
        self.assertIsNone(self.api.ref)

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
                self.sleep.assert_not_called()
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
                self.assertEqual({asset["name"]: {"size": asset["size"], "sha256": asset["digest"][7:]}
                                  for asset in self.api.assets}, self.manifest)

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

    def test_empty_first_page_with_next_link_stops_preflight(self):
        api, open_response = self.mock_http_operation("/releases", "GET")
        response = open_response.return_value.__enter__.return_value
        response.status = 200
        response.headers = http.client.HTTPMessage()
        response.headers.add_header(
            "Link", f'<https://api.github.com/repositories/{REPOSITORY_ID}/releases?per_page=100&page=2>; rel="next"',
        )
        response.read.return_value = b"[]"
        self.assert_cli_failure("stage=preflight category=pagination-invalid", api=api)
        self.assertEqual(self.api.calls, [("/releases?per_page=100&page=1", "GET", None)])
        self.assertEqual(self.mutations(), [])

    def test_full_page_with_only_backward_links_still_checks_next_page_for_conflicts(self):
        self.api.unrelated = [{"id": index + 1000, "tag_name": "other"} for index in range(200)]
        self.api.release = {"id": 31, "tag_name": TAG, "draft": True}

        def request(path, *args, **kwargs):
            result = self.api(path, *args, **kwargs)
            if path == "/releases?per_page=100&page=2":
                items, _ = result
                return items, {"prev": 1, "first": 1}
            return result

        self.assert_cli_failure("stage=preflight category=conflicting-release", api=request)
        self.assertEqual(self.api.calls[-1], ("/releases?per_page=100&page=3", "GET", None))
        self.assertEqual(self.mutations(), [])

    def test_full_terminal_page_checks_and_accepts_empty_next_page(self):
        self.api.unrelated = [{"id": index + 1000, "tag_name": "other"} for index in range(100)]
        api, open_response = self.mock_http_operation("/releases", "GET")
        response = open_response.return_value.__enter__.return_value
        response.status = 200
        response.headers = http.client.HTTPMessage()
        response.headers.add_header(
            "Link", f'<https://api.github.com/repositories/{REPOSITORY_ID}/releases?per_page=100&page=1>; rel="last"',
        )
        response.read.side_effect = [json.dumps(self.api.unrelated).encode(), b"[]"]
        self.assertFalse(self.publisher(api=api).conflicts())
        self.assertEqual(self.api.calls, [(f"/releases?per_page=100&page={page}", "GET", None) for page in (1, 2)])

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

    def test_missing_public_tag_reports_http_status_and_preserves_published_state(self):
        self.api.create_ref = False
        path = "/git/ref/tags/" + TAG
        api, open_response = self.mock_http_operation(path, "GET")
        error = urllib.error.HTTPError(
            "https://example.invalid" + path, 404, "synthetic response text", {}, None,
        )
        self.addCleanup(error.close)
        open_response.side_effect = error
        self.assert_cli_failure("stage=final-verification operation=read-tag-ref http_status=404", api=api)
        self.assertEqual(self.api.calls[-1][:2], (path, "GET"))
        self.assertEqual(len(self.mutations()), 11)
        self.assertIs(self.api.release["draft"], False)
        self.assertEqual(len(self.api.assets), 9)
        self.assertEqual(self.mutations()[-1][1], "PATCH")
        self.assertIsNone(self.api.ref)

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
            with self.subTest(key=key):
                self.assert_cli_failure("stage=draft-creation-response category=validation-failed")
                self.assertEqual(len(self.mutations()), 1)
                self.assertEqual(self.api.calls[-1][:2], ("/releases", "POST"))
                self.sleep.assert_not_called()
                self.assertEqual(self.api.assets, [])
                self.assertIs(self.api.release["draft"], True)
                self.assertIsNone(self.api.ref)

    def test_draft_observation_rechecks_every_page_and_tag_before_upload(self):
        first_page, second_page = (f"/releases?per_page=100&page={page}" for page in (1, 2))
        self.api.unrelated = [{"id": index + 1000, "tag_name": "other"} for index in range(100)]

        def hide(path, method, result):
            if path == second_page and self.sleep.call_count < 3:
                result.clear()

        wait_boundaries = []
        self.sleep.side_effect = lambda _: wait_boundaries.append(len(self.api.calls))
        self.api.after = hide
        self.assertEqual(self.publisher().publish(), 31)
        effects = self.mutations()
        self.assertEqual([effect[:2] for effect in effects], [
            ("/releases", "POST"),
            *(("/releases/31/assets?name=" + name, "POST") for name in sorted(self.manifest)),
            ("/releases/31", "PATCH"),
        ])
        start = self.api.calls.index(effects[0]) + 1
        first_upload = self.api.calls.index(effects[1])
        reads = ("/releases/31", first_page, second_page, "/git/ref/tags/" + TAG)
        observation = [(path, "GET", None) for path in reads]
        self.assertEqual(self.api.calls[start:first_upload], observation * 4)
        self.assertEqual(wait_boundaries, [start + count * len(observation) for count in (1, 2, 3)])
        self.assertEqual(self.sleep.call_args_list, [call(5), call(15), call(40)])

    def test_draft_listing_absence_exhausts_wait_before_first_upload(self):
        def hide(path, method, result):
            if self.api.release is not None and path.startswith("/releases?"):
                result.clear()

        self.api.after = hide
        self.assert_cli_failure("stage=draft-observation category=draft-listing-absent")
        self.assertEqual(self.sleep.call_args_list, [call(5), call(15), call(40)])
        self.assertEqual(len(self.mutations()), 1)
        start = self.api.calls.index(self.mutations()[0]) + 1
        reads = ("/releases/31", "/releases?per_page=100&page=1", "/git/ref/tags/" + TAG)
        observation = [(path, "GET", None) for path in reads]
        self.assertEqual(self.api.calls[start:], observation * 4)
        self.assertEqual(self.api.assets, [])
        self.assertIs(self.api.release["draft"], True)
        self.assertIsNone(self.api.ref)

    def test_draft_observation_validates_pagination_before_upload(self):
        canonical = f"https://api.github.com/repositories/{REPOSITORY_ID}/releases"
        next_link = f'<{canonical}?page=2&per_page=100>; rel="next"'
        last_link = f'<{canonical}?per_page=100&page=2>; rel="last"'
        bound = {"id": 31, "tag_name": TAG, "name": TAG, "target_commitish": SHA,
                 "body": NOTES, "draft": True, "prerelease": False}
        short_page = [bound]
        full_page = [bound, *({"id": index + 1000, "tag_name": "other"} for index in range(99))]
        conflict_page = [{**bound, "id": 32}]
        wrong_repository = "https://api.github.com/repositories/124/releases"
        cases = (
            ("short page with continuation", [short_page, conflict_page], [f"{next_link}, {last_link}"],
             "conflicting-release"),
            ("empty first page with continuation", [[]], [next_link], "pagination-invalid"),
            ("empty advertised continuation", [short_page, []], [next_link, last_link], "pagination-invalid"),
            ("malformed link", [short_page], ["synthetic malformed header"], "pagination-invalid"),
            ("wrong destination", [short_page], [next_link.replace("api.github.com", "example.invalid")],
             "pagination-invalid"),
            ("wrong repository", [short_page], [next_link.replace(canonical, wrong_repository)], "pagination-invalid"),
            ("mixed repository IDs", [short_page], [next_link, last_link.replace(canonical, wrong_repository)],
             "pagination-invalid"),
            ("skipped page", [short_page], [next_link.replace("page=2", "page=3")], "pagination-invalid"),
            ("missing continuation", [short_page], [last_link], "pagination-invalid"),
            ("early terminal page", [short_page, conflict_page], [next_link, last_link.replace("page=2", "page=3")],
             "pagination-invalid"),
            ("conflict after advertised end", [full_page, conflict_page], [last_link.replace("page=2", "page=1")],
             "pagination-invalid"),
        )
        for scenario, pages, links, category in cases:
            with self.subTest(scenario=scenario):
                self.api = FakeGitHub()
                api, open_response = self.mock_http_operation("/releases", "GET", after_creation=True)
                response = open_response.return_value.__enter__.return_value
                response.status = 200
                first_headers, second_headers = http.client.HTTPMessage(), http.client.HTTPMessage()
                for link in links:
                    first_headers.add_header("Link", link)
                second_headers.add_header(
                    "Link", '<https://api.github.com/repos/example/project/releases?per_page=100&page=1>; rel="prev"',
                )

                def respond(request, *, timeout):
                    first = request.full_url.endswith("&page=1")
                    response.headers = first_headers if first else second_headers
                    response.read.return_value = json.dumps(pages[0 if first else 1]).encode()
                    return open_response.return_value

                open_response.side_effect = respond
                self.assert_cli_failure(f"stage=draft-observation category={category}", api=api)
                self.assertEqual([entry.args[0].full_url for entry in open_response.call_args_list], [
                    f"https://api.github.com/repos/example/project/releases?per_page=100&page={page}"
                    for page in range(1, len(pages) + 1)
                ])
                self.sleep.assert_not_called()
                self.assertEqual([effect[:2] for effect in self.mutations()], [("/releases", "POST")])
                self.assertEqual(self.api.assets, [])
                self.assertIs(self.api.release["draft"], True)
                self.assertIsNone(self.api.ref)

    def test_draft_observation_rejects_binding_and_pagination_discrepancies_without_waiting(self):
        by_id, tag_ref = "/releases/31", "/git/ref/tags/" + TAG
        first_page, second_page = (f"/releases?per_page=100&page={page}" for page in (1, 2))
        bound = {"id": 31, "tag_name": TAG, "name": TAG, "target_commitish": SHA,
                 "body": NOTES, "draft": True, "prerelease": False}
        conflicting = {**bound, "id": 32}
        full_page = [bound, *({"id": index + 1000, "tag_name": "other"} for index in range(99))]
        wrong_tag = {"ref": "refs/tags/" + TAG, "object": {"type": "commit", "sha": "c" * 40}}
        cases = (
            ("wrong direct ID", {by_id: conflicting}, "release-by-id-binding-mismatch"),
            ("changed direct notes", {by_id: {**bound, "body": "other"}}, "release-by-id-binding-mismatch"),
            ("changed listed notes", {first_page: [{**bound, "body": "other"}]}, "listed-release-binding-mismatch"),
            ("changed listed tag", {first_page: [{**bound, "tag_name": "other"}]}, "listed-release-binding-mismatch"),
            ("wrong listed ID", {first_page: [conflicting]}, "conflicting-release"),
            ("second matching ID", {first_page: [bound, conflicting]}, "conflicting-release"),
            ("duplicate on next page", {first_page: full_page, second_page: [bound]}, "release-listing-invalid"),
            ("invalid page", {first_page: {"items": []}}, "release-listing-invalid"),
            ("conflicting tag during absence", {first_page: [], tag_ref: wrong_tag}, "tag-binding-mismatch"),
            ("invalid tag during absence", {first_page: [], tag_ref: None}, "tag-binding-mismatch"),
        )
        for scenario, responses, category in cases:
            with self.subTest(scenario=scenario):
                self.api = FakeGitHub()

                def request(path, method="GET", *args, **kwargs):
                    result = self.api(path, method, *args, **kwargs)
                    if method == "GET" and self.api.release is not None and path in responses:
                        if kwargs.get("page") is not None:
                            return responses[path], {}
                        return responses[path]
                    return result

                self.assert_cli_failure(f"stage=draft-observation category={category}", api=request)
                self.sleep.assert_not_called()
                self.assertEqual([effect[:2] for effect in self.mutations()], [("/releases", "POST")])
                self.assertEqual(self.api.assets, [])
                self.assertIs(self.api.release["draft"], True)
                self.assertIsNone(self.api.ref)

    def test_draft_observation_stops_on_transport_failure_during_recheck(self):
        def fail_after_wait(path, method, result):
            if self.api.release is not None and path.startswith("/releases?"):
                if self.sleep.called:
                    raise urllib.error.URLError("synthetic transport detail")
                result.clear()

        self.api.after = fail_after_wait
        self.assert_cli_failure("stage=draft-observation category=transport-error")
        self.sleep.assert_called_once_with(5)
        self.assertEqual([effect[:2] for effect in self.mutations()], [("/releases", "POST")])
        self.assertEqual(self.api.assets, [])

    def test_draft_missing_from_later_observation_stops_without_waiting(self):
        def hide_after_upload(path, method, result):
            if path.startswith("/releases?") and len(self.api.assets) == 9:
                result.clear()

        self.api.after = hide_after_upload
        self.assert_cli_failure("stage=asset-verification category=bound-release-not-listed")
        self.sleep.assert_not_called()
        self.assertEqual(len(self.mutations()), 10)
        self.assertIs(self.api.release["draft"], True)
        self.assertIsNone(self.api.ref)

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
            with self.subTest(symlink=symlink):
                self.assert_cli_failure("stage=asset-file-verification category=validation-failed")
                self.assertEqual(len(self.mutations()), 1)
                self.assertEqual(self.api.assets, [])

    def test_uncertain_create_upload_and_transition_effects_are_never_retried_or_erased(self):
        cases = (
            ("draft-creation", "/releases", "POST", 0, True),
            ("asset-upload", "/releases/31/assets", "POST", 1, True),
            ("publish-transition", "/releases/31", "PATCH", 9, False),
        )
        for stage, target, verb, asset_count, draft in cases:
            with self.subTest(stage=stage):
                self.api = FakeGitHub()

                def uncertain(path, method, result):
                    if path.partition("?")[0] == target and method == verb:
                        raise OSError("Synthetic transport detail")

                self.api.after = uncertain
                self.assert_cli_failure(f"stage={stage} category=io-error")
                effects = self.mutations()
                self.assertIsNotNone(self.api.release)
                self.assertEqual(sum(path == "/releases" and method == "POST" for path, method, _ in effects), 1)
                self.assertEqual(len(self.api.assets), asset_count)
                self.assertIs(self.api.release["draft"], draft)
                self.assertTrue(all(method in ("POST", "PATCH") for _, method, _ in effects))
                self.assertEqual(len(effects), 1 + asset_count + (0 if draft else 1))


class WorkflowTransferTests(unittest.TestCase):
    """Exercise current workflow scripts with synthetic bytes and injected signer/Git reads."""

    def test_staging_upload_allowlist_and_verified_transfer_agree(self):
        workflow = (Path(__file__).resolve().parents[2] / ".github/workflows/release-github.yml").read_text()
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name).resolve()
        checkout, temporary = root / "checkout", root / "temporary"
        checkout.mkdir()
        temporary.mkdir()
        original = Path.cwd()
        self.addCleanup(os.chdir, original)
        os.chdir(checkout)

        def script(step):
            block = workflow.split("      - name: " + step + "\n", 1)[1]
            return textwrap.dedent(block.split("<<'PY'\n", 1)[1].split("\n          PY", 1)[0])

        paths = [
            "apps/phone_flutter/build/app/outputs/bundle/release/app-release.aab",
            "apps/phone_flutter/build/app/outputs/flutter-apk/app-release.apk",
            "apps/wear_android/app/build/outputs/bundle/release/app-release.aab",
            "apps/wear_android/app/build/outputs/apk/release/app-release.apk",
            "apps/watchface_wff/build/outputs/bundle/release/WardPulseWatchFace-release.aab",
            "apps/watchface_wff/build/outputs/apk/release/WardPulseWatchFace-release.apk",
            "apps/wear_android/watchface_push/build/outputs/apk/release/watchface_push-release.apk",
        ]
        names = ["wardpulse-phone-1.2.3-code9.aab", "WardPulse-1.2.3-Android.apk",
                 "wardpulse-wear-1.2.3-code10.aab", "WardPulse-1.2.3-WearOS.apk",
                 "wardpulse-legacy-1.2.3-code4.aab", "WardPulse-1.2.3-WatchFace-WearOS5Plus.apk",
                 "wardpulse-push-1.2.3-code6.apk"]
        push = b"synthetic Push bytes"
        for index, path in enumerate(paths):
            binary = Path(path)
            binary.parent.mkdir(parents=True, exist_ok=True)
            binary.write_bytes(push if index == 6 else ("synthetic binary " + str(index)).encode())
        generated = Path("apps/wear_android/app/build/generated/defaultWatchFace/release/assets/default_watchface.apk")
        generated.parent.mkdir(parents=True)
        generated.write_bytes(push)
        for index, entry in ((2, "base/assets/default_watchface.apk"), (3, "assets/default_watchface.apk")):
            with zipfile.ZipFile(paths[index], "w") as archive:
                archive.writestr(entry, push)

        upload_pin = "d02f85820e60d6cf49e939a1af72a84c17d3ce107c840b4e9d3ac0f3946f078e"
        push_pin = "04fa77a4feabb08e8c71fb1ddc32000c63f18e6ff5967e3b5b8acbd5b36d4950"
        def signer(arguments, **kwargs):
            if arguments[0] == "jarsigner":
                return Mock(returncode=0, stdout="jar verified.\n")
            if arguments[0] == "keytool":
                return Mock(returncode=0, stdout="SHA256: " + upload_pin + "\n")
            self.assertTrue(arguments[0].endswith("/apksigner"))
            pin = push_pin if arguments[-1] == paths[6] else upload_pin
            return Mock(returncode=0, stdout="Verifies\nSigner #1 certificate SHA-256 digest: " + pin + "\n")

        environment = {"RELEASE_VERSION": "1.2.3", "RELEASE_TAG": "v1.2.3", "SOURCE_SHA": SHA,
                       "PHONE_CODE": "9", "WEAR_CODE": "10", "LEGACY_CODE": "4", "PUSH_CODE": "6",
                       "UPLOAD_CERT_SHA256": upload_pin, "PUSH_CERT_SHA256": push_pin,
                       "RELEASE_PRIVATE_DIR": str(temporary / "private"), "ANDROID_HOME": str(root / "sdk"),
                       "RUNNER_TEMP": str(temporary), "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "2",
                       "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REF": "refs/heads/main",
                       "BUILD_RESULT": "success", "DISPATCH_SHA": SHA, "DISPATCH_TAG": "v1.2.3",
                       "BUILD_ARTIFACT_ID": "42", "BUILD_RUN_ID": "123", "BUILD_RUN_ATTEMPT": "2",
                       "BUILD_ARTIFACT_NAME": "wardpulse-android-v1.2.3-123-attempt-2",
                       "GITHUB_ENV": str(temporary / "environment")}
        with patch.dict(os.environ, environment, clear=True), patch("subprocess.run", side_effect=signer):
            exec(script("Verify signatures and stage the explicit allowlist"), {})
        stage = temporary / "wardpulse-android-release-artifacts"
        expected_names = set(names) | {"SHA256SUMS", "provenance.json"}
        self.assertEqual({path.name for path in stage.iterdir()}, expected_names)
        for name, path in zip(names, paths):
            self.assertEqual((stage / name).read_bytes(), Path(path).read_bytes())

        allowlist = re.findall(r"^            \$\{\{ runner.temp \}\}/wardpulse-android-release-artifacts/(.+)$",
                               workflow, re.MULTILINE)
        for key in ("version", "phone_code", "wear_code", "legacy_code", "push_code"):
            value = "1.2.3" if key == "version" else environment[key.upper()]
            allowlist = [name.replace("${{ steps.versions.outputs." + key + " }}", value) for name in allowlist]
        self.assertEqual(len(allowlist), 9)
        self.assertEqual(set(allowlist), expected_names)

        sources = {"apps/phone_flutter/pubspec.yaml": "version: 1.2.3+9\n",
                   "apps/wear_android/app/build.gradle.kts": 'versionCode = 10\nversionName = "1.2.3"\n',
                   "apps/watchface_wff/build.gradle.kts": 'versionCode = 4\nversionName = "1.2.3"\n',
                   "apps/wear_android/watchface_push/build.gradle.kts":
                       'versionName = "1.2.3"\n}.orElse(6)\n'}
        def git(arguments, **kwargs):
            if arguments == ["git", "rev-parse", "HEAD"]:
                return SHA + "\n"
            self.assertEqual(arguments[:2], ["git", "show"])
            sha, path = arguments[2].split(":", 1)
            self.assertEqual(sha, SHA)
            return sources[path]

        with patch.dict(os.environ, environment, clear=True), patch("subprocess.check_output", side_effect=git):
            exec(script("Bind successful build outputs to the original dispatch and source"), {})
        environment.update(line.split("=", 1) for line in Path(environment["GITHUB_ENV"]).read_text().splitlines())
        expected = json.loads(Path(environment["EXPECTED_TRANSFER"]).read_text())
        self.assertEqual(expected["binaries"], {name: push_pin if name == names[-1] else upload_pin for name in names})
        for path in stage.iterdir():
            shutil.copyfile(path, Path(environment["TRANSFER_DIR"]) / path.name)
        with patch.dict(os.environ, environment, clear=True):
            exec(script("Independently verify the nine received files and receipts"), {})
        manifest = json.loads(Path(environment["VERIFIED_TRANSFER"]).read_text())
        self.assertEqual(manifest, {path.name: {"size": path.stat().st_size,
                                               "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                                    for path in stage.iterdir()})
        provenance = json.loads((stage / "provenance.json").read_bytes())
        self.assertEqual([record["file"] for record in provenance["binaries"]], names)
        self.assertEqual((provenance["source_sha"], provenance["build_run_id"], provenance["build_run_attempt"]),
                         (SHA, "123", "2"))


if __name__ == "__main__":
    unittest.main()
