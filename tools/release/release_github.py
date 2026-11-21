#!/usr/bin/env python3
"""Publish only the independently verified transfer from the original dispatch checkout."""

import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import urllib.error
import urllib.parse
import urllib.request

from prepare_release import readiness


def require(condition):
    if not condition:
        raise ValueError("Release publication invariant failed")


def options(draft, prerelease, latest):
    require(draft in ("true", "false") and prerelease in ("true", "false"))
    require(latest in ("true", "false", "automatic"))
    draft, prerelease = draft == "true", prerelease == "true"
    if latest == "true" and (draft or prerelease):
        raise ValueError("latest=true requires a published normal release")
    policy = "legacy" if latest == "automatic" and not (draft or prerelease) else latest
    return draft, prerelease, "false" if policy == "automatic" else policy


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class UnexpectedHTTPStatus(ValueError):
    def __init__(self, code):
        super().__init__("Unexpected GitHub response status")
        self.code = code


class GitHub:
    def __init__(self, token, repository):
        require(token and re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository))
        self.token, self.repository = token, repository
        self.opener = urllib.request.build_opener(NoRedirect())

    def __call__(self, path, method="GET", payload=None, missing=False, upload=None, *, on_response=None):
        host = "https://uploads.github.com" if upload is not None else "https://api.github.com"
        headers = {"Authorization": "Bearer " + self.token, "Accept": "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "WardPulse-release"}
        data = None if payload is None else json.dumps(payload).encode()
        if payload is not None:
            headers["Content-Type"] = "application/json"
        if upload is not None:
            data, size = upload
            headers.update({"Content-Type": "application/octet-stream", "Content-Length": str(size)})
        request = urllib.request.Request(host + "/repos/" + self.repository + path,
                                         data=data, headers=headers, method=method)
        try:
            with self.opener.open(request, timeout=60) as response:
                if response.status != (201 if method == "POST" else 200):
                    raise UnexpectedHTTPStatus(response.status)
                if on_response is not None:
                    on_response()
                return json.load(response)
        except urllib.error.HTTPError as error:
            if missing and error.code == 404:
                return None
            raise


class Publisher:
    def __init__(self, api, sha, tag, notes, manifest, directory, draft, prerelease, latest):
        self.api, self.sha, self.tag, self.notes = api, sha, tag, notes
        self.manifest, self.directory = manifest, directory
        self.stage, self.operation = "preflight", None
        self.draft, self.prerelease, self.latest = options(draft, prerelease, latest)
        require(re.fullmatch(r"[0-9a-f]{40}", sha) and notes.strip())
        require(len(manifest) == 9)
        for name, item in manifest.items():
            require(re.fullmatch(r"[A-Za-z0-9_.-]+", name) and name not in (".", ".."))
            require(type(item["size"]) is int and item["size"] > 0)
            require(re.fullmatch(r"[0-9a-f]{64}", item["sha256"]))

    def request(self, operation, *args, response_stage=None, **kwargs):
        # Retain the predefined operation only when the request raises.
        self.operation = operation
        if response_stage is not None:
            def on_response():
                self.stage = response_stage

            kwargs["on_response"] = on_response
        result = self.api(*args, **kwargs)
        self.operation = None
        return result

    def pages(self, operation, path):
        seen = set()
        for page in range(1, 1001):
            items = self.request(operation, f"{path}?per_page=100&page={page}")
            require(type(items) is list and len(items) <= 100)
            for item in items:
                require(type(item) is dict and type(item.get("id")) is int and item["id"] > 0)
                require(item["id"] not in seen)
                seen.add(item["id"])
                yield item
            if len(items) < 100:
                return
        raise ValueError("Pagination did not finish")

    def binding(self, release, release_id, draft):
        require(type(release.get("id")) is int and release["id"] == release_id)
        require(release.get("draft") is draft and release.get("prerelease") is self.prerelease)
        require(release.get("tag_name") == self.tag and release.get("name") == self.tag)
        require(release.get("target_commitish") == self.sha and release.get("body") == self.notes)

    def conflicts(self, allowed=None, draft=True):
        matches = []
        for release in self.pages("list-releases", "/releases"):
            require(type(release.get("tag_name")) is str)
            if release["tag_name"] == self.tag:
                require(release["id"] == allowed)
                self.binding(release, allowed, draft)
                matches.append(release["id"])
        require(matches == ([] if allowed is None else [allowed]))

    def tag_binding(self, required=False):
        ref = self.request("read-tag-ref", "/git/ref/tags/" + urllib.parse.quote(self.tag, safe=""),
                           missing=not required)
        if ref is None:
            require(not required)  # Only a draft may lack a real Git ref.
            return
        require(ref.get("ref") == "refs/tags/" + self.tag)
        obj, seen = ref["object"], set()
        for _ in range(16):
            target = obj["sha"]
            require(re.fullmatch(r"[0-9a-f]{40}", target) and target not in seen)
            seen.add(target)
            if obj["type"] == "commit":
                require(target == self.sha)
                return
            require(obj["type"] == "tag")
            annotation = self.request("read-annotated-tag", "/git/tags/" + target)
            require(annotation["sha"] == target)
            obj = annotation["object"]
        raise ValueError("Tag could not be peeled")

    def observe(self, release_id, draft):
        self.binding(self.request("read-release", f"/releases/{release_id}"), release_id, draft)
        self.conflicts(release_id, draft)
        self.tag_binding(required=not draft)

    def asset_binding(self, asset, name):
        expected = self.manifest[name]
        require(asset.get("name") == name and asset.get("state") == "uploaded")
        require(type(asset.get("size")) is int and asset["size"] == expected["size"])
        digest = asset.get("digest")
        if digest is not None and digest != "":
            require(digest == "sha256:" + expected["sha256"])

    def verify_assets(self, release_id, uploaded):
        assets = list(self.pages("list-release-assets", f"/releases/{release_id}/assets"))
        require(len(assets) == 9 and {asset["name"] for asset in assets} == self.manifest.keys())
        for asset in assets:
            self.asset_binding(asset, asset["name"])
            require(asset["id"] == uploaded[asset["name"]])

    def publish(self):
        self.stage, self.operation = "preflight", None
        self.conflicts()  # Authenticated, draft-inclusive listing; never GET-by-tag absence.
        self.tag_binding()
        # Repeat immediately before POST; this is not an atomic exclusion lock.
        self.conflicts()
        self.tag_binding()
        self.stage = "draft-creation"
        created = self.request("create-draft", "/releases", "POST", {
            "tag_name": self.tag, "target_commitish": self.sha, "name": self.tag,
            "body": self.notes, "draft": True, "prerelease": self.prerelease, "make_latest": "false",
        }, response_stage="draft-creation-response")
        release_id = created["id"]
        require(type(release_id) is int and release_id > 0)
        self.binding(created, release_id, True)
        self.stage = "draft-observation"
        self.observe(release_id, True)
        uploaded = {}
        for name, expected in sorted(self.manifest.items()):
            self.stage = "asset-file-verification"
            path = self.directory / name
            require(stat.S_ISREG(path.lstat().st_mode))
            with path.open("rb") as stream:
                require(os.fstat(stream.fileno()).st_size == expected["size"])
                require(hashlib.file_digest(stream, "sha256").hexdigest() == expected["sha256"])
                stream.seek(0)
                self.stage = "asset-upload"
                asset = self.request("upload-asset",
                                     f"/releases/{release_id}/assets?name=" + urllib.parse.quote(name, safe=""),
                                     "POST", upload=(stream, expected["size"]),
                                     response_stage="asset-upload-response")
            self.asset_binding(asset, name)
            require(type(asset.get("id")) is int and asset["id"] > 0 and asset["id"] not in uploaded.values())
            uploaded[name] = asset["id"]
        self.stage = "asset-verification"
        self.observe(release_id, True)
        self.verify_assets(release_id, uploaded)
        if not self.draft:
            self.stage = "publish-transition"
            self.observe(release_id, True)
            final = self.request("publish-release", f"/releases/{release_id}", "PATCH", {
                "tag_name": self.tag, "target_commitish": self.sha, "name": self.tag,
                "body": self.notes,
                "draft": False, "prerelease": self.prerelease, "make_latest": self.latest,
            })
            self.binding(final, release_id, False)
        self.stage = "final-verification"
        self.observe(release_id, self.draft)
        self.verify_assets(release_id, uploaded)
        return release_id


def failure_detail(error, stage, operation):
    if operation is not None and isinstance(error, (urllib.error.HTTPError, UnexpectedHTTPStatus)):
        status = error.code
        if type(status) is int and 100 <= status <= 999:
            return f"stage={stage} operation={operation} http_status={status}"
        category = "invalid-http-status"
    elif isinstance(error, KeyboardInterrupt):
        category = "interrupted"
    elif isinstance(error, (urllib.error.URLError, http.client.HTTPException)):
        category = "transport-error"
    elif isinstance(error, (OSError, subprocess.SubprocessError)):
        category = "io-error"
    elif isinstance(error, (json.JSONDecodeError, UnicodeError)):
        category = "invalid-data"
    elif isinstance(error, (ValueError, AttributeError, KeyError, TypeError)):
        category = "validation-failed"
    else:
        category = "unexpected-error"
    return f"stage={stage} category={category}"


def main():
    publisher = None
    try:
        env = os.environ
        flags = tuple(env[key] for key in ("RELEASE_DRAFT", "RELEASE_PRERELEASE", "RELEASE_LATEST"))
        options(*flags)
        require(env["GITHUB_EVENT_NAME"] == "workflow_dispatch" and env["GITHUB_REF"] == "refs/heads/main")
        root = Path(__file__).resolve().parents[2]
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True, stderr=subprocess.DEVNULL)
        require(head.strip() == env["SOURCE_SHA"])
        ready = readiness(root, env["RELEASE_TAG"])
        require(ready["version"] == env["RELEASE_VERSION"])
        manifest = json.loads(Path(env["VERIFIED_TRANSFER"]).read_text())
        publisher = Publisher(GitHub(env["GH_TOKEN"], env["GITHUB_REPOSITORY"]), env["SOURCE_SHA"],
                              env["RELEASE_TAG"], ready["notes"], manifest, Path(env["TRANSFER_DIR"]), *flags)
        release_id = publisher.publish()
        print(f"Release {release_id} confirmed with requested draft/prerelease state and all nine assets.")
    except (Exception, KeyboardInterrupt) as error:
        stage, operation = (publisher.stage, publisher.operation) if publisher is not None else ("preflight", None)
        raise SystemExit("Publication failed; preserve all release/tag/asset state, including any partial or "
                         "public release, for Owner reconciliation. Do not blindly retry.\n"
                         f"Publication diagnostic {failure_detail(error, stage, operation)}") from None


if __name__ == "__main__":
    main()
