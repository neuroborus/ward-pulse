"""Neutral offline contract tests; all HTTP is injected, filesystem tests use real scratch."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, call, patch

import release_google_play as play


TAG, SOURCE, DISPATCH, ANNOTATION = "v1.2.3", "a" * 40, "b" * 40, "c" * 40
BASE = "https://api.github.com/repos/example/project"
NAMES = [
    "wardpulse-phone-1.2.3-code9.aab", "wardpulse-phone-1.2.3-code9.apk",
    "wardpulse-wear-1.2.3-code10.aab", "wardpulse-wear-1.2.3-code10.apk",
    "wardpulse-legacy-1.2.3-code4.aab", "wardpulse-legacy-1.2.3-code4.apk",
    "wardpulse-push-1.2.3-code6.apk",
]


def encoded(value):
    return json.dumps(value).encode()


class HistoricalCheckout:
    dispatch_sha = DISPATCH

    def __init__(self, root):
        self.root, self.allowed, self.reads = root, True, []
        self.sources = {
            "phone": "version: 1.2.3+9\n",
            "wear": 'versionCode = 10\nversionName = "1.2.3"\n',
            "legacy": 'versionCode = 4\nversionName = "1.2.3"\n',
            "push": 'val pushVersionCode = providers.gradleProperty("wardpulsePushVersionCode").map { value ->\n'
                    '    value.toIntOrNull()?.takeIf { it > 0 }\n}.orElse(6)\n'
                    'versionCode = pushVersionCode.get()\nversionName = "1.2.3"\n',
        }

    def ancestor(self, sha):
        play.require(self.allowed and sha == SOURCE)

    def source(self, sha, path):
        play.require(sha == SOURCE)  # Current-main versions must never be consulted.
        self.reads.append((sha, path))
        return self.sources[next(key for key, value in play.SOURCES.items() if value == path)]


class Release:
    def __init__(self, root):
        self.checkout, self.calls, self.responses = HistoricalCheckout(root), [], {}
        self.blobs = {name: ("neutral bytes " + name).encode() for name in NAMES}
        self.hashes = {name: hashlib.sha256(data).hexdigest() for name, data in self.blobs.items()}
        self.provenance = {
            "source_sha": SOURCE, "tag": TAG, "version": "1.2.3", "build_run_id": "123", "build_run_attempt": "2",
            "binaries": [{"file": name, "sha256": self.hashes[name], "signer_sha256":
                "04fa77a4feabb08e8c71fb1ddc32000c63f18e6ff5967e3b5b8acbd5b36d4950" if "-push-" in name else
                "d02f85820e60d6cf49e939a1af72a84c17d3ce107c840b4e9d3ac0f3946f078e"} for name in NAMES],
            "checks_completed": [
                "Immutable checkout and four source versions/code allocation",
                "Shared fixtures and watch payload contract",
                "Canonical WFF drift and official XML validator",
                "Both imported private keys/passwords and fixed public certificate pins",
                "Guarded AAB and direct release APK producers",
                "PrepareDefaultWatchFace official Push validation and AGP embedding",
                "Three jarsigner strict AAB verifications and keytool certificate pins",
                "Four apksigner APK verifications and certificate pins",
                "Exact Push producer/generated/Wear AAB/Wear installer/staged byte equality",
                "Seven staged binary SHA-256 comparisons",
            ],
        }
        self.sums = "".join(f"{digest}  {name}\n" for name, digest in self.hashes.items()).encode()
        self.assets = [{"id": index, "name": name, "state": "uploaded", "size": len(self.body(name)),
                        "digest": None, "url": BASE + f"/releases/assets/{index}"}
                       for index, name in enumerate(NAMES + ["SHA256SUMS", "provenance.json"], 1)]
        self.release = {"id": 40, "tag_name": TAG, "draft": False, "prerelease": False,
                        "published_at": "2026-01-02T03:04:05Z", "url": BASE + "/releases/40",
                        "target_commitish": "untrusted-branch"}
        self.listing = [self.release]
        self.ref = {"ref": "refs/tags/" + TAG, "object": {"type": "tag", "sha": ANNOTATION}}
        self.annotation = {"sha": ANNOTATION, "object": {"type": "commit", "sha": SOURCE}}

    def body(self, name):
        return self.sums if name == "SHA256SUMS" else encoded(self.provenance) if name == "provenance.json" else self.blobs[name]

    def refresh(self):
        for asset in self.assets:
            asset["size"] = len(self.body(asset["name"]))

    def transport(self, url, headers, limit):
        self.calls.append((url, headers.copy(), limit))
        if url in self.responses:
            return self.responses[url]
        routes = {"/releases/tags/" + TAG: self.release, "/releases?per_page=100&page=1": self.listing,
                  "/git/ref/tags/" + TAG: self.ref, "/git/tags/" + ANNOTATION: self.annotation,
                  "/releases/40/assets?per_page=100&page=1": self.assets}
        if url.removeprefix(BASE) in routes:
            return 200, {}, encoded(routes[url.removeprefix(BASE)])
        for asset in self.assets:
            if url == asset["url"]:
                return 200, {}, self.body(asset["name"])
        raise AssertionError("Unexpected offline request")


class PreparationTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name).resolve()
        self.checkout = self.root / "checkout"
        self.checkout.mkdir()
        self.output = self.root / "prepared"
        environment = patch.dict(os.environ, {"GH_TOKEN": "offline-token", "GITHUB_RUN_ID": "999", "GITHUB_RUN_ATTEMPT": "9"})
        environment.start()
        self.addCleanup(environment.stop)

    def execute(self, fixture, tag=TAG):
        return play.prepare(tag, fixture.checkout, play.GitHub("example/project", fixture.transport), self.output)

    def reject(self, change):
        fixture = Release(self.checkout)
        change(fixture)
        with self.assertRaises(play.PreparationError):
            self.execute(fixture)
        self.assertFalse(self.output.exists())

    def test_historical_release_retains_exact_bytes_and_only_downloads_four_assets(self):
        fixture = Release(self.checkout)
        for asset in fixture.assets:
            asset["digest"] = "sha256:" + hashlib.sha256(fixture.body(asset["name"])).hexdigest()
        identity = self.execute(fixture)
        expected = {NAMES[0], NAMES[2], "SHA256SUMS", "provenance.json", "preparation.json"}
        self.assertEqual({p.name for p in self.output.iterdir()}, expected)
        self.assertEqual((self.output / NAMES[0]).read_bytes(), fixture.blobs[NAMES[0]])
        self.assertEqual((self.output / NAMES[2]).read_bytes(), fixture.blobs[NAMES[2]])
        self.assertEqual(identity["source_sha"], SOURCE)
        self.assertEqual(identity["dispatch_sha"], DISPATCH)
        self.assertEqual(identity["tag_chain"], [{"type": "tag", "sha": ANNOTATION}, {"type": "commit", "sha": SOURCE}])
        self.assertEqual(len(identity["assets"]), 9)
        provenance = json.loads((self.output / "provenance.json").read_bytes())
        self.assertEqual((provenance["build_run_id"], provenance["build_run_attempt"]), ("123", "2"))
        for name, asset in identity["assets"].items():
            self.assertEqual(asset["id"], next(item["id"] for item in fixture.assets if item["name"] == name))
            if name in expected:
                self.assertEqual(asset["verified_sha256"], hashlib.sha256((self.output / name).read_bytes()).hexdigest())
        downloads = [url for url, _, _ in fixture.calls if "/releases/assets/" in url]
        self.assertEqual(downloads, [BASE + f"/releases/assets/{i}" for i in (8, 9, 1, 3)])
        self.assertEqual(len(fixture.checkout.reads), 4)
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)
        for path in self.output.iterdir():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertNotIn(b"offline-token", path.read_bytes())
            self.assertNotIn(b"https://", path.read_bytes())

    def test_missing_and_empty_optional_digests_and_lightweight_tag_are_supported(self):
        fixture = Release(self.checkout)
        for index, asset in enumerate(fixture.assets):
            if index % 2:
                asset.pop("digest")
            else:
                asset["digest"] = ""
        fixture.ref["object"] = {"type": "commit", "sha": SOURCE}
        self.assertEqual(self.execute(fixture)["source_sha"], SOURCE)

    def test_source_and_version_rejections(self):
        mutations = [lambda f: setattr(f.checkout, "allowed", False)]
        for surface, old, new in [("phone", "+9", "+8"), ("wear", "= 10", "= 12"),
                                  ("legacy", "= 4", "= 0"), ("push", "orElse(6)", "orElse(2147483648)"),
                                  ("push", "pushVersionCode.get()", "6"), ("phone", "1.2.3", "1.2.4"),
                                  ("wear", "1.2.3", "1.2.4"), ("legacy", "1.2.3", "1.2.4"),
                                  ("push", "1.2.3", "1.2.4")]:
            mutations.append(lambda f, s=surface, a=old, b=new: f.checkout.sources.__setitem__(s, f.checkout.sources[s].replace(a, b)))
        mutations.append(lambda f: f.checkout.sources.__setitem__("wear", f.checkout.sources["wear"] + 'versionName = "1.2.3"\n'))
        for change in mutations:
            with self.subTest(change=change):
                self.reject(change)
        for tag in ("latest", "v1.2.3-rc1", "v01.2.3", "../v1.2.3"):
            fixture = Release(self.checkout)
            with self.subTest(tag=tag), self.assertRaises(play.PreparationError):
                self.execute(fixture, tag)
            self.assertEqual(fixture.calls, [])

    def test_release_tag_and_asset_identity_rejections(self):
        changes = [lambda f: f.release.update(draft=True), lambda f: f.release.update(prerelease=True),
                   lambda f: f.release.update(published_at=None), lambda f: f.release.update(tag_name="v1.2.4"),
                   lambda f: f.listing.append(dict(f.release, id=41)),
                   lambda f: f.annotation.update(sha="d" * 40),
                   lambda f: f.annotation.update(object={"type": "tag", "sha": ANNOTATION}),
                   lambda f: f.ref.update(object={"type": "tree", "sha": SOURCE}),
                   lambda f: f.assets.pop(), lambda f: f.assets[0].update(name="../bundle.aab"),
                   lambda f: f.assets[0].update(id=True),
                   lambda f: f.assets[0].update(id=2, url=BASE + "/releases/assets/2"),
                   lambda f: f.assets[0].update(name=NAMES[1]), lambda f: f.assets[0].update(state="new"),
                   lambda f: f.assets[0].update(url="https://example.invalid/asset"),
                   lambda f: f.assets[0].update(size=play.BUNDLE_LIMIT + 1),
                   lambda f: f.assets[0].update(digest="md5:unsupported")]
        for index, change in enumerate(changes):
            with self.subTest(case=index):
                self.reject(change)

    def test_receipt_contract_rejections(self):
        changes = [lambda f: f.provenance.update(source_sha=DISPATCH), lambda f: f.provenance.update(tag="v1.2.4"),
                   lambda f: f.provenance.update(version="1.2.4"), lambda f: f.provenance.update(build_run_id=123),
                   lambda f: f.provenance.update(build_run_attempt="0"), lambda f: f.provenance.pop("build_run_attempt"),
                   lambda f: f.provenance.update(extra=True),
                   lambda f: f.provenance["checks_completed"].pop(), lambda f: f.provenance["binaries"].pop(),
                   lambda f: f.provenance["binaries"][0].update(signer_sha256="0" * 64),
                   lambda f: f.provenance["binaries"][6].update(signer_sha256=play.UPLOAD_PIN),
                   lambda f: f.provenance["binaries"][0].update(sha256="0" * 64),
                   lambda f: f.provenance["binaries"].__setitem__(0, f.provenance["binaries"][1]),
                   lambda f: setattr(f, "sums", f.sums + f.sums.splitlines(keepends=True)[0]),
                   lambda f: setattr(f, "sums", f.sums.replace(NAMES[0].encode(), b"../bundle.aab")),
                   lambda f: setattr(f, "sums", b"invalid\n"),
                   lambda f: f.assets[1].update(digest="sha256:" + "0" * 64)]
        for index, change in enumerate(changes):
            with self.subTest(case=index):
                def mutate(f):
                    change(f)
                    f.refresh()
                self.reject(mutate)
        for body in (b'{"source_sha":"a","source_sha":"b"}', b"{", b"NaN", b"\xff"):
            with self.subTest(body=body):
                fixture = Release(self.checkout)
                fixture.assets[8]["size"] = len(body)
                fixture.responses[BASE + "/releases/assets/9"] = (200, {}, body)
                with self.assertRaisesRegex(play.PreparationError, "^Invalid JSON receipt or metadata.$"):
                    self.execute(fixture)
                self.assertFalse(self.output.exists())

    def test_actual_byte_hash_size_and_supplied_digest_failures(self):
        for name in (NAMES[0], NAMES[2]):
            with self.subTest(name=name):
                self.reject(lambda f: f.blobs.__setitem__(name, b"x" * len(f.blobs[name])))
        self.reject(lambda f: f.assets[0].update(size=1))
        self.reject(lambda f: f.assets[7].update(digest="sha256:" + "0" * 64))

    def test_safe_redirect_strips_credentials_and_never_retains_urls(self):
        fixture = Release(self.checkout)
        signed = "https://release-assets.githubusercontent.com/neutral?signature=offline"
        fixture.responses[BASE + "/releases/assets/1"] = (302, {"location": signed}, b"")
        fixture.responses[signed] = (200, {}, fixture.blobs[NAMES[0]])
        self.execute(fixture)
        redirected = [headers for url, headers, _ in fixture.calls if url == signed]
        self.assertEqual(len(redirected), 1)
        self.assertNotIn("Authorization", redirected[0])
        self.assertTrue(all(headers.get("Authorization") == "Bearer offline-token"
                            for url, headers, _ in fixture.calls if url.startswith(BASE)))
        self.assertNotIn(signed.encode(), (self.output / "preparation.json").read_bytes())

    def test_redirect_and_transport_failure_boundaries(self):
        targets = ["http://release-assets.githubusercontent.com/a", "https://example.invalid/a",
                   "https://release-assets.githubusercontent.com.example.invalid/a",
                   "https://user@release-assets.githubusercontent.com/a", "file:///a", "/relative",
                   "https://release-assets.githubusercontent.com:443/a", "https://release-assets.githubusercontent.com/a#fragment",
                   "https://release-assets.githubusercontent.com/a\r\nheader", "https://release-assets.githubusercontent.com/a\\b"]
        for target in targets:
            fixture = Release(self.checkout)
            fixture.responses[BASE + "/releases/assets/1"] = (302, {"location": target}, b"")
            with self.subTest(target=target), self.assertRaises(play.PreparationError):
                self.execute(fixture)
            self.assertEqual(fixture.calls[-1][0], BASE + "/releases/assets/1")
            self.assertFalse(self.output.exists())
        for status in (301, 307, 404):
            self.reject(lambda f: f.responses.update({BASE + "/releases/assets/1": (status, {}, b"diagnostic")}))
        loop = "https://objects.githubusercontent.com/loop"
        fixture = Release(self.checkout)
        fixture.responses.update({BASE + "/releases/assets/1": (302, {"location": loop}, b""),
                                  loop: (302, {"location": loop}, b"")})
        with self.assertRaises(play.PreparationError):
            self.execute(fixture)
        self.assertEqual(sum(url == loop for url, _, _ in fixture.calls), 3)
        with self.assertRaisesRegex(play.PreparationError, "^GitHub read failed.$"):
            play.GitHub("example/project", Mock(side_effect=OSError("offline-token signed-url"))).json("/releases")
        with patch.dict(os.environ, {"GH_TOKEN": ""}), self.assertRaises(play.PreparationError):
            play.GitHub("example/project", fixture.transport)

    def test_metadata_redirects_and_oversized_downloads_fail_without_following(self):
        fixture = Release(self.checkout)
        fixture.responses[BASE + "/releases/tags/" + TAG] = (
            302, {"location": "https://objects.githubusercontent.com/neutral"}, b"")
        with self.assertRaises(play.PreparationError):
            self.execute(fixture)
        self.assertEqual(len(fixture.calls), 1)
        self.reject(lambda f: f.responses.update({BASE + "/releases/assets/8":
                    (200, {}, b"x" * (play.RECEIPT_LIMIT + 1))}))

    def test_http_adapter_has_bounded_reads_timeout_and_no_automatic_redirects(self):
        response = Mock(status=200, headers={})
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        response.read.return_value = b"neutral"
        with patch.object(play.urllib.request, "build_opener") as build:
            build.return_value.open.return_value = response
            self.assertEqual(play.http_read(BASE, {}, 10), (200, {}, b"neutral"))
        self.assertEqual(build.return_value.open.call_args.kwargs, {"timeout": 30})
        response.read.assert_called_once_with(11)
        self.assertIsInstance(build.call_args.args[0], play.urllib.request.ProxyHandler)
        self.assertIsNone(build.call_args.args[1].redirect_request(None, None, 302, None, None, "https://example.invalid"))

    def test_real_filesystem_rejects_reuse_symlinks_checkout_and_traversal(self):
        existing = self.root / "existing"
        existing.mkdir()
        marker = existing / "marker"
        marker.write_bytes(b"preserve")
        link = self.root / "link"
        link.symlink_to(existing, target_is_directory=True)
        alias = Path("/" + str(self.checkout)) / "child"  # POSIX double-slash spelling of the same checkout.
        for output in (existing, link, link / "child", self.checkout / "child", alias, self.root / ".." / "escape", Path("relative")):
            with self.subTest(output=output), self.assertRaises(play.PreparationError):
                play.retain(output, self.checkout, {"bundle.aab": b"verified"})
        self.assertEqual(marker.read_bytes(), b"preserve")
        self.assertEqual(list(existing.iterdir()), [marker])
        self.assertEqual(list(self.checkout.iterdir()), [])
        with self.assertRaises(play.PreparationError):
            play.retain(self.output, self.checkout, {"good.aab": b"verified", "../escape": b"reject"})
        self.assertFalse(self.output.exists())

    def test_original_checkout_guards_and_git_failures(self):
        tool = self.checkout / play.TOOL
        tool.parent.mkdir(parents=True)
        tool.write_text("original\n")
        outputs = {("rev-parse", "--show-toplevel"): str(self.checkout), ("rev-parse", "HEAD"): DISPATCH,
                   ("config", "--get", "remote.origin.url"): "https://github.com/example/project.git",
                   ("status", "--porcelain", "--untracked-files=all"): "", ("show", DISPATCH + ":" + play.TOOL): "original\n"}
        with patch.object(play.Path, "cwd", return_value=self.checkout), patch.object(play, "__file__", str(tool)), \
                patch.object(play.Checkout, "git", side_effect=lambda *args: outputs[args]):
            play.Checkout("example/project", DISPATCH, "workflow_dispatch", "refs/heads/main")
            for key, value in [(('rev-parse', 'HEAD'), SOURCE), (('status', '--porcelain', '--untracked-files=all'), "modified"),
                               (('config', '--get', 'remote.origin.url'), "https://example.invalid/project")]:
                original = outputs[key]
                outputs[key] = value
                with self.subTest(key=key), self.assertRaises(play.PreparationError):
                    play.Checkout("example/project", DISPATCH, "workflow_dispatch", "refs/heads/main")
                outputs[key] = original
            for event, ref in (("push", "refs/heads/main"), ("workflow_dispatch", "refs/heads/other")):
                with self.assertRaises(play.PreparationError):
                    play.Checkout("example/project", DISPATCH, event, ref)
            tool.write_text("modified\n")
            with self.assertRaises(play.PreparationError):
                play.Checkout("example/project", DISPATCH, "workflow_dispatch", "refs/heads/main")
        checkout = play.Checkout.__new__(play.Checkout)
        checkout.root, checkout.dispatch_sha = self.checkout, DISPATCH
        with patch.object(checkout, "git", side_effect=[SOURCE, ""]) as git:
            checkout.ancestor(SOURCE)
        self.assertEqual(git.call_args_list, [call("rev-parse", "--verify", SOURCE + "^{commit}"),
                                             call("merge-base", "--is-ancestor", SOURCE, DISPATCH)])
        with patch.object(play.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "git")) as run:
            with self.assertRaises(play.PreparationError):
                checkout.ancestor(SOURCE)
        self.assertEqual(run.call_args.kwargs["env"]["GIT_NO_REPLACE_OBJECTS"], "1")
        self.assertNotIn("GH_TOKEN", run.call_args.kwargs["env"])


if __name__ == "__main__":
    unittest.main()
