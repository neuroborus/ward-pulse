#!/usr/bin/env python3
"""Prepare published WardPulse bundles, or apply verified bytes in one Play edit."""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


UPLOAD_PIN = "d02f85820e60d6cf49e939a1af72a84c17d3ce107c840b4e9d3ac0f3946f078e"
PUSH_PIN = "04fa77a4feabb08e8c71fb1ddc32000c63f18e6ff5967e3b5b8acbd5b36d4950"
CHECKS = [
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
]
SOURCES = {
    "phone": "apps/phone_flutter/pubspec.yaml",
    "wear": "apps/wear_android/app/build.gradle.kts",
    "legacy": "apps/watchface_wff/build.gradle.kts",
    "push": "apps/wear_android/watchface_push/build.gradle.kts",
}
TOOL = "tools/release-google-play/release_google_play.py"
SHA = r"[0-9a-f]{40}"
HASH = r"[0-9a-f]{64}"
STABLE = r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
JSON_LIMIT = 2 * 1024 * 1024
RECEIPT_LIMIT = 1024 * 1024
BUNDLE_LIMIT = 512 * 1024 * 1024
PLAY_BASE = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/app.wardpulse/edits"
PLAY_UPLOAD = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/app.wardpulse/edits"
OPERATION_MARKER = ".play-operation"


class PreparationError(ValueError):
    """A fixed, sanitized diagnostic; remote response details must never escape."""


def require(condition, message="Preparation contract rejected."):
    if not condition:
        raise PreparationError(message)


def matches(pattern, value):
    return type(value) is str and re.fullmatch(pattern, value) is not None


def positive(value):
    return type(value) is int and value > 0


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_json(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result)
            result[key] = value
        return result

    try:
        return json.loads(data, object_pairs_hook=unique,
                          parse_constant=lambda _: require(False))
    except (ValueError, UnicodeError, RecursionError):
        raise PreparationError("Invalid JSON receipt or metadata.") from None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def http_read(url, headers, limit):
    """One bounded GET, with neither automatic redirects nor ambient proxies."""
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    request = urllib.request.Request(url, headers=headers, method="GET")
    try:
        response = opener.open(request, timeout=30)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        body = response.read(limit + 1) if response.status == 200 else b""
        return response.status, dict((k.lower(), v) for k, v in response.headers.items()), body


class GitHub:
    def __init__(self, repository, transport=http_read):
        require(matches(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,99}/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}", repository))
        token = os.environ.get("GH_TOKEN", "")
        require(matches(r"[!-~]{1,4096}", token), "GH_TOKEN must be supplied through the environment.")
        self.base = "https://api.github.com/repos/" + repository
        self.transport, self._token = transport, token

    def request(self, url, limit, authenticated):
        headers = {"Accept": "application/vnd.github+json" if limit == JSON_LIMIT else "application/octet-stream",
                   "User-Agent": "WardPulse-Play-prepare", "X-GitHub-Api-Version": "2022-11-28"}
        if authenticated:
            require(url.startswith(self.base + "/"))
            headers["Authorization"] = "Bearer " + self._token
        try:
            status, response_headers, body = self.transport(url, headers, limit)
            require(type(body) is bytes and len(body) <= limit)
            return status, response_headers, body
        except Exception:
            raise PreparationError("GitHub read failed.") from None

    def json(self, path):
        status, _, body = self.request(self.base + path, JSON_LIMIT, True)
        require(status == 200, "GitHub metadata unavailable.")
        return read_json(body)

    def download(self, asset):
        limit = RECEIPT_LIMIT if asset["name"] in ("SHA256SUMS", "provenance.json") else BUNDLE_LIMIT
        url = self.base + "/releases/assets/" + str(asset["id"])
        for hop in range(4):
            status, headers, body = self.request(url, limit, hop == 0)
            if status == 200:
                require(len(body) == asset["size"], "Asset size mismatch.")
                if asset["digest"]:
                    require(asset["digest"] == "sha256:" + sha256(body), "Asset digest mismatch.")
                return body
            require(status == 302 and hop < 3, "Unsupported asset response.")
            url = headers.get("location", "")
            require(type(url) is str and all(32 < ord(c) < 127 for c in url))
            parsed = urllib.parse.urlsplit(url)
            require(parsed.scheme == "https" and parsed.netloc in (
                "release-assets.githubusercontent.com", "objects.githubusercontent.com")
                and not parsed.fragment and "\\" not in url, "Unsafe asset redirect.")
        raise PreparationError("Asset redirect limit exceeded.")


class Checkout:
    """Only the original main checkout supplies executable tooling; releases supply data."""

    def __init__(self, repository, dispatch_sha, event, ref):
        require(event == "workflow_dispatch" and ref == "refs/heads/main")
        require(matches(SHA, dispatch_sha))
        self.root = Path.cwd().resolve()
        self.dispatch_sha = dispatch_sha
        require(Path(__file__).resolve() == self.root / TOOL, "Run tooling from the original checkout.")
        require(self.git("rev-parse", "--show-toplevel").strip() == str(self.root))
        require(self.git("rev-parse", "HEAD").strip() == dispatch_sha, "Dispatch checkout mismatch.")
        require(self.git("config", "--get", "remote.origin.url").strip() in (
            "https://github.com/" + repository, "https://github.com/" + repository + ".git",
            "git@github.com:" + repository + ".git"), "Checkout repository mismatch.")
        require(not self.git("status", "--porcelain", "--untracked-files=all"), "Checkout must be clean.")
        require((self.root / TOOL).read_bytes() == self.source(dispatch_sha, TOOL).encode(),
                "Tooling differs from the original dispatch.")

    def git(self, *args):
        environment = {"PATH": os.environ.get("PATH", os.defpath), "GIT_CONFIG_NOSYSTEM": "1",
                       "GIT_CONFIG_GLOBAL": os.devnull, "GIT_NO_REPLACE_OBJECTS": "1",
                       "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"}
        try:
            return subprocess.run(["git", "-c", "core.fsmonitor=false", "--no-pager", *args],
                                  cwd=self.root, env=environment, check=True, timeout=30,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  encoding="utf-8").stdout
        except (OSError, subprocess.SubprocessError, UnicodeError):
            raise PreparationError("Required immutable Git data unavailable.") from None

    def source(self, sha, path):
        require(matches(SHA, sha) and path in (*SOURCES.values(), TOOL))
        text = self.git("show", sha + ":" + path)
        require(len(text) <= JSON_LIMIT)
        return text

    def ancestor(self, sha):
        require(self.git("rev-parse", "--verify", sha + "^{commit}").strip() == sha)
        self.git("merge-base", "--is-ancestor", sha, self.dispatch_sha)


def one(pattern, source):
    values = re.findall(pattern, source, re.MULTILINE)
    require(len(values) == 1, "Unsupported or ambiguous version declaration.")
    return values[0]


def binary_contract(checkout, sha, tag):
    codes = {}
    for surface, path in SOURCES.items():
        text = checkout.source(sha, path)
        if surface == "phone":
            one(r"^version:.*$", text)
            version, code = one(r"^version: ([0-9.]+)\+([0-9]{1,10})$", text)
        else:
            one(r"^\s*versionName\s*=.*$", text)
            version = one(r'^\s*versionName = "([0-9.]+)"$', text)
            declaration = one(r"^\s*versionCode\s*=.*$", text).strip()
            if surface == "push":
                require(declaration == "versionCode = pushVersionCode.get()")
                one(r"^val pushVersionCode\s*=.*$", text)
                code = one(r'^val pushVersionCode = providers\.gradleProperty\("wardpulsePushVersionCode"\)'
                           r'\.map \{ value ->\n[\s\S]*?^\}\.orElse\(([0-9]{1,10})\)$', text)
            else:
                code = one(r"^\s*versionCode = ([0-9]{1,10})$", text)
        require(version == tag[1:], "Tag and historical source versions differ.")
        codes[surface] = int(code)
    require(all(0 < code <= 2147483647 for code in codes.values()))
    require(codes["phone"] % 2 == 1 and codes["wear"] == codes["phone"] + 1)
    return {f"wardpulse-{surface}-{tag[1:]}-code{code}.{extension}":
            PUSH_PIN if surface == "push" else UPLOAD_PIN
            for surface, code in codes.items()
            for extension in (("apk",) if surface == "push" else ("aab", "apk"))}


def observe(github, tag):
    release = github.json("/releases/tags/" + tag)
    require(type(release) is dict and positive(release.get("id")))
    require(release.get("tag_name") == tag and release.get("draft") is False
            and release.get("prerelease") is False
            and matches(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", release.get("published_at")))
    require(release.get("url") == github.base + "/releases/" + str(release["id"]))
    ids, matching = set(), []
    for page in range(1, 101):
        items = github.json(f"/releases?per_page=100&page={page}")
        require(type(items) is list and len(items) <= 100)
        for item in items:
            require(type(item) is dict and positive(item.get("id")) and item["id"] not in ids
                    and type(item.get("tag_name")) is str)
            ids.add(item["id"])
            if item.get("tag_name") == tag:
                matching.append(item)
        if len(items) < 100:
            break
    else:
        raise PreparationError("Release listing limit exceeded.")
    require(len(matching) == 1 and all(matching[0].get(k) == release[k] for k in
            ("id", "tag_name", "draft", "prerelease", "published_at", "url")), "Ambiguous release identity.")
    ref = github.json("/git/ref/tags/" + tag)
    require(type(ref) is dict and ref.get("ref") == "refs/tags/" + tag)
    obj, chain = ref.get("object"), []
    for _ in range(16):
        require(type(obj) is dict and matches(SHA, obj.get("sha")))
        require(obj["sha"] not in [entry["sha"] for entry in chain])
        require(obj.get("type") in ("tag", "commit"))
        chain.append({"sha": obj["sha"], "type": obj["type"]})
        if obj["type"] == "commit":
            return release, chain
        annotation = github.json("/git/tags/" + obj["sha"])
        require(type(annotation) is dict and annotation.get("sha") == obj["sha"])
        obj = annotation.get("object")
    raise PreparationError("Tag peeling limit exceeded.")


def asset_contract(github, release_id, binaries):
    items = github.json(f"/releases/{release_id}/assets?per_page=100&page=1")
    require(type(items) is list and len(items) == 9)
    assets, ids = {}, set()
    for item in items:
        require(type(item) is dict and positive(item.get("id")) and item["id"] not in ids)
        name, digest = item.get("name"), item.get("digest")
        require(type(name) is str and name in set(binaries) | {"SHA256SUMS", "provenance.json"}
                and name not in assets and item.get("state") == "uploaded")
        limit = RECEIPT_LIMIT if name in ("SHA256SUMS", "provenance.json") else BUNDLE_LIMIT
        require(positive(item.get("size")) and item["size"] <= limit)
        require(digest in (None, "") or matches("sha256:" + HASH, digest))
        require(item.get("url") == github.base + "/releases/assets/" + str(item["id"]))
        assets[name] = {"id": item["id"], "name": name, "size": item["size"], "digest": digest or None}
        ids.add(item["id"])
    return assets


def verify_receipts(sums, provenance_bytes, binaries, assets, sha, tag):
    hashes = {}
    try:
        for line in sums.decode("ascii").splitlines():
            match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9_.-]+)", line)
            require(match is not None)
            digest, name = match.groups()
            require(name in binaries and name not in hashes)
            hashes[name] = digest
    except UnicodeError:
        raise PreparationError("Invalid checksum receipt.") from None
    require(hashes.keys() == binaries.keys())
    provenance = read_json(provenance_bytes)
    require(type(provenance) is dict and provenance.keys() == {
        "source_sha", "tag", "version", "build_run_id", "build_run_attempt", "binaries", "checks_completed"})
    require(provenance["source_sha"] == sha and provenance["tag"] == tag and provenance["version"] == tag[1:])
    require(all(matches(r"[1-9][0-9]{0,19}", provenance[k]) for k in ("build_run_id", "build_run_attempt")))
    require(provenance["checks_completed"] == CHECKS)
    records = provenance["binaries"]
    require(type(records) is list and len(records) == 7)
    seen = set()
    for record in records:
        require(type(record) is dict and record.keys() == {"file", "sha256", "signer_sha256"})
        name = record["file"]
        require(type(name) is str and name in binaries and name not in seen)
        require(record["sha256"] == hashes[name] and record["signer_sha256"] == binaries[name])
        require(not assets[name]["digest"] or assets[name]["digest"] == "sha256:" + hashes[name])
        seen.add(name)
    return hashes


def retain(output, checkout_root, files):
    """Create a private fresh directory via no-follow directory FDs; never overwrite."""
    output = Path(output)
    require(output.anchor == "/" and ".." not in output.parts
            and not output.is_relative_to(checkout_root), "Output must be outside the checkout.")
    parent_fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    directory_fd, written = None, []
    try:
        for component in output.parent.parts[1:]:
            next_fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
            os.close(parent_fd)
            parent_fd = next_fd
        os.mkdir(output.name, mode=0o700, dir_fd=parent_fd)
        directory_fd = os.open(output.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
        for name, data in files.items():
            require(matches(r"[A-Za-z0-9_.-]+", name) and name not in (".", ".."))
            fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory_fd)
            written.append(name)
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
    except Exception:
        if directory_fd is not None:
            for name in written:
                os.unlink(name, dir_fd=directory_fd)
            os.rmdir(output.name, dir_fd=parent_fd)
        raise PreparationError("Could not retain verified preparation safely.") from None
    finally:
        if directory_fd is not None:
            os.close(directory_fd)
        os.close(parent_fd)


def preparation_identity(tag, checkout, github):
    require(type(tag) is str and len(tag) <= 100 and matches(STABLE, tag), "Explicit stable tag required.")
    release, chain = observe(github, tag)
    sha = chain[-1]["sha"]
    checkout.ancestor(sha)
    binaries = binary_contract(checkout, sha, tag)
    assets = asset_contract(github, release["id"], binaries)
    identity = {"schema_version": 1, "repository": github.base.removeprefix("https://api.github.com/repos/"),
                "dispatch_sha": checkout.dispatch_sha, "dispatch_ref": "refs/heads/main",
                "release_id": release["id"], "published_at": release["published_at"], "tag": tag,
                "source_sha": sha, "tag_chain": chain, "assets": assets}
    return identity, binaries


def bundle_names(binaries):
    return [name for name in binaries
            if name.startswith(("wardpulse-phone-", "wardpulse-wear-")) and name.endswith(".aab")]


def prepare(tag, checkout, github, output):
    identity, binaries = preparation_identity(tag, checkout, github)
    assets = identity["assets"]
    files = {name: github.download(assets[name]) for name in ("SHA256SUMS", "provenance.json")}
    hashes = verify_receipts(files["SHA256SUMS"], files["provenance.json"], binaries, assets, identity["source_sha"], tag)
    for name in bundle_names(binaries):
        files[name] = github.download(assets[name])
        require(sha256(files[name]) == hashes[name], "Bundle bytes differ from receipts.")
    for name, data in files.items():
        assets[name]["verified_sha256"] = sha256(data)
    files["preparation.json"] = (json.dumps(identity, indent=2) + "\n").encode()
    retain(output, checkout.root, files)
    return identity


@contextmanager
def preparation_directory(path, checkout_root):
    """Hold the retained directory by FD, rejecting symlink components and traversal."""
    path = Path(path)
    require(path.anchor == "/" and ".." not in path.parts and not path.is_relative_to(checkout_root),
            "Preparation must be an absolute directory outside the checkout.")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for component in path.parts[1:]:
            next_fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        yield fd
    except OSError:
        raise PreparationError("Could not access retained preparation safely.") from None
    finally:
        os.close(fd)


def retained_read(directory, name, limit):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= limit, "Invalid retained file.")
        data = stream.read(limit + 1)
    require(0 < len(data) <= limit, "Invalid retained file size.")
    return data


def verified_preparation(directory, checkout, github):
    saved = read_json(retained_read(directory, "preparation.json", JSON_LIMIT))
    require(type(saved) is dict, "Invalid preparation identity.")
    identity, binaries = preparation_identity(saved.get("tag"), checkout, github)
    names = bundle_names(binaries)
    retained = names + ["SHA256SUMS", "provenance.json"]
    require(set(os.listdir(directory)) - {OPERATION_MARKER} == set(retained + ["preparation.json"]),
            "Unexpected retained preparation contents.")
    files = {name: retained_read(directory, name, BUNDLE_LIMIT if name in names else RECEIPT_LIMIT)
             for name in retained}
    assets = identity["assets"]
    hashes = verify_receipts(files["SHA256SUMS"], files["provenance.json"], binaries, assets,
                             identity["source_sha"], identity["tag"])
    for name, data in files.items():
        digest = sha256(data)
        require(len(data) == assets[name]["size"] and (not assets[name]["digest"]
                or assets[name]["digest"] == "sha256:" + digest), "Retained size or digest mismatch.")
        require(name not in names or digest == hashes[name], "Retained bundle differs from receipts.")
        assets[name]["verified_sha256"] = digest
    require(json.dumps(saved, sort_keys=True) == json.dumps(identity, sort_keys=True),
            "Preparation or published GitHub identity changed.")
    return [(int(one(r"-code([0-9]+)\.aab$", name)), files[name], hashes[name]) for name in names]


class PlayError(PreparationError):
    """Only fixed diagnostics, never tokens or remote response bodies."""


def play_http(method, url, headers, body, limit):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        response = opener.open(request, timeout=60)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, response.read(limit + 1) if response.status == 200 else b""


class Play:
    def __init__(self, transport=play_http):
        token = os.environ.get("PLAY_ACCESS_TOKEN", "")
        require(matches(r"[!-~]{1,4096}", token), "PLAY_ACCESS_TOKEN must be supplied through the environment.")
        self._token, self.transport, self.attempted = token, transport, False
        self.directory = None

    def request(self, method, path="", body=None, upload=False):
        mutation = method != "GET"
        if mutation:
            # Exclusive, durable intent survives interruption; a fresh run cannot replay it.
            fd = os.open(OPERATION_MARKER, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=self.directory)
            with os.fdopen(fd, "wb") as stream:
                stream.write(b"Unreconciled Play operation. Inspect server state before removing this marker.\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.fsync(self.directory)
            self.attempted = True
        headers = {"Authorization": "Bearer " + self._token,
                   "Content-Type": "application/octet-stream" if upload else "application/json"}
        data = body if upload else (json.dumps(body).encode() if body is not None else None)
        try:
            url = (PLAY_UPLOAD if upload else PLAY_BASE) + path
            status, response = self.transport(method, url, headers, data, JSON_LIMIT)
            require(type(status) is int and 100 <= status <= 599)
            if status != 200:
                # A failed mutation may have reached the service; retain the reconciliation barrier.
                message = "Play HTTP " + str(status) + "; check Console bootstrap, permissions and Wear setup."
                if mutation:
                    message += " Operation failed or is uncertain; reconcile server state before retrying."
                raise PlayError(message)
            require(type(response) is bytes and len(response) <= JSON_LIMIT)
            result = read_json(response)
            require(type(result) is dict)
            return result
        except PlayError:
            raise
        except Exception:
            if mutation:
                raise PlayError("Play operation failed or is uncertain; reconcile server state before retrying.") from None
            raise PlayError("Play state unavailable; check Console bootstrap, permissions and Wear setup.") from None

    def confirmed(self):
        os.unlink(OPERATION_MARKER, dir_fd=self.directory)
        os.fsync(self.directory)


def release_codes(release):
    require(type(release) is dict, "Invalid Play release.")
    codes = release.get("versionCodes")
    require(type(codes) is list and 0 < len(codes) <= 10000
            and all(matches(r"[1-9][0-9]{0,9}", code) and int(code) <= 2147483647 for code in codes)
            and len(set(codes)) == len(codes), "Ambiguous Play version codes; resolve in Console.")
    return {int(code) for code in codes}


def track_state(track, code, status):
    """Conservative read-modify-write: retain state or demand an explicit Console decision."""
    releases = track.get("releases", [])
    require(type(releases) is list and len(releases) <= 2, "Ambiguous track releases; resolve in Console.")
    by_status, seen = {}, set()
    for release in releases:
        codes = release_codes(release)
        state = release.get("status")
        require(state in ("draft", "completed") and state not in by_status and not seen.intersection(codes),
                "Conflicting draft or rollout; resolve in Console.")
        require(max(codes) <= code, "Refusing to roll back a newer version.")
        by_status[state] = release
        seen.update(codes)
    completed, draft = by_status.get("completed"), by_status.get("draft")
    if completed and code in release_codes(completed):
        require(status == "completed", "Requested bundle is already completed; cannot save a draft.")
        require(draft is None, "Conflicting draft; resolve in Console.")
        return track
    if draft:
        require(release_codes(draft) == {code}, "Conflicting draft or retained codes; resolve in Console.")
        if status == "draft":
            return track
    desired = dict(draft, status=status) if draft else {"versionCodes": [str(code)], "status": status}
    if status == "draft":
        return dict(track, releases=releases + [desired])
    require(completed is None or len(release_codes(completed)) == 1,
            "Completed release retains multiple codes; resolve retention in Console.")
    return dict(track, releases=[desired])


def verify_track_response(result, desired):
    message = "Uncertain Play track update response."
    releases = result.get("releases")
    require(type(releases) is list and len(releases) == len(desired["releases"]), message)
    normalized = []
    for actual, expected in zip(releases, desired["releases"]):
        require(type(actual) is dict, message)
        actual = dict(actual)
        # Play generates a release name when the request omits it.
        if "name" not in expected and "name" in actual:
            require(type(actual.pop("name")) is str, message)
        normalized.append(actual)
    require(dict(result, releases=normalized) == desired, message)


def apply(preparation, checkout, github, play, phone_track, wear_track, status):
    require(matches(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,99}", phone_track)
            and matches(r"wear:[A-Za-z0-9][A-Za-z0-9_.-]{0,99}", wear_track)
            and status in ("draft", "completed"), "Explicit mobile/Wear track IDs and status required.")
    with preparation_directory(preparation, checkout.root) as directory:
        bundles = verified_preparation(directory, checkout, github)
        require(OPERATION_MARKER not in os.listdir(directory),
                "Unreconciled Play operation marker exists; inspect server state before retrying.")
        play.directory = directory
        edit = play.request("POST", body={})
        require(matches(r"[A-Za-z0-9_-]{1,200}", edit.get("id")), "Uncertain Play edit creation.")
        edit = "/" + edit["id"]
        play.confirmed()
        tracks_response = play.request("GET", edit + "/tracks")
        bundle_response = play.request("GET", edit + "/bundles")
        tracks, listed = {}, {}
        items = tracks_response.get("tracks")
        require(type(items) is list and len(items) <= 1000, "Invalid Play track listing.")
        consumed = set()
        for track in items:
            require(type(track) is dict and type(track.get("track")) is str
                    and track["track"] not in tracks, "Ambiguous Play tracks.")
            tracks[track["track"]] = track
            releases = track.get("releases", [])
            require(type(releases) is list and len(releases) <= 1000, "Invalid Play track state.")
            for release in releases:
                consumed.update(release_codes(release))
        require(phone_track in tracks and wear_track in tracks,
                "Selected mobile/Wear tracks must already exist; configure them in Console.")
        items = bundle_response.get("bundles", [])
        require(type(items) is list and len(items) <= 10000, "Invalid Play bundle listing.")
        for bundle in items:
            require(type(bundle) is dict and positive(bundle.get("versionCode"))
                    and bundle["versionCode"] <= 2147483647 and matches(HASH, bundle.get("sha256"))
                    and bundle["versionCode"] not in listed, "Ambiguous Play bundles.")
            listed[bundle["versionCode"]] = bundle["sha256"]
        updates = []
        for track_id, (code, _, digest) in zip((phone_track, wear_track), bundles):
            require(code not in listed or listed[code] == digest, "Version code has conflicting Play bytes.")
            require(code in listed or code not in consumed,
                    "Consumed code is absent from bundle listing; resolve in Console.")
            updates.append(track_state(tracks[track_id], code, status))
        for code, data, digest in bundles:
            if code not in listed:
                result = play.request("POST", edit + "/bundles?uploadType=media", data, upload=True)
                require(type(result.get("versionCode")) is int and result["versionCode"] == code
                        and result.get("sha256") == digest, "Uncertain upload: Play code/hash mismatch.")
                play.confirmed()
        for desired in updates:
            track_id = desired["track"]
            if desired != tracks[track_id]:
                result = play.request("PUT", edit + "/tracks/" + urllib.parse.quote(track_id, safe=""), desired)
                verify_track_response(result, desired)
                play.confirmed()
        for action in (":validate", ":commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW"):
            result = play.request("POST", edit + action)
            require(result.get("id") == edit[1:], "Uncertain Play validation or commit response.")
            play.confirmed()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", help="Stable release tag for read-only preparation")
    parser.add_argument("--output", help="Fresh absolute directory outside the checkout")
    commands = parser.add_subparsers(dest="command")
    applying_parser = commands.add_parser("apply", help="Apply retained verified bundles in one Play edit")
    applying_parser.add_argument("--preparation", required=True)
    applying_parser.add_argument("--phone-track", required=True)
    applying_parser.add_argument("--wear-track", required=True)
    applying_parser.add_argument("--status", required=True, choices=("draft", "completed"))
    args = parser.parse_args()
    applying = args.command == "apply"
    if applying and (args.tag is not None or args.output is not None):
        parser.error("apply cannot be combined with preparation options")
    if not applying and (args.tag is None or args.output is None):
        parser.error("preparation requires --tag and --output")
    play = None
    try:
        repository = os.environ["GITHUB_REPOSITORY"]
        checkout = Checkout(repository, os.environ["GITHUB_SHA"], os.environ["GITHUB_EVENT_NAME"], os.environ["GITHUB_REF"])
        github = GitHub(repository)
        if applying:
            play = Play()
            apply(args.preparation, checkout, github, play, args.phone_track, args.wear_track, args.status)
        else:
            prepare(args.tag, checkout, github, args.output)
    except Exception as error:
        if applying:
            attempted = play is not None and play.attempted
            print("Play apply failed after a Play operation was attempted." if attempted
                  else "Apply verification failed; no Play operation was attempted.", file=sys.stderr)
            if isinstance(error, PreparationError):
                print(str(error), file=sys.stderr)
            if attempted:
                print("Inspect server state and any .play-operation marker before retrying.", file=sys.stderr)
        else:
            print("GitHub release preparation failed; no Play operation was attempted.", file=sys.stderr)
        return 1
    print("Play edit committed with requested " + args.status + " tracks; review and delivery remain unverified."
          if applying else "Verified phone/Wear bundles and sanitized identities retained for later re-observation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
