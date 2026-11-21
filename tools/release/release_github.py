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
from time import sleep
import urllib.error
import urllib.parse
import urllib.request

from prepare_release import readiness


NOT_FOUND = object()


class ValidationError(ValueError):
    def __init__(self, category):
        super().__init__("Release publication invariant failed")
        self.category = category


def require(condition, category="validation-failed"):
    if not condition:
        raise ValidationError(category)


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
    def __init__(self, token, repository, repository_id):
        require(token and re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository))
        require(re.fullmatch(r"[1-9][0-9]*", repository_id))
        self.token, self.repository = token, repository
        self.repository_id = repository_id
        self.opener = urllib.request.build_opener(NoRedirect())

    def __call__(self, path, method="GET", payload=None, missing=False, upload=None, *,
                 on_response=None, page=None):
        host = "https://uploads.github.com" if upload is not None else "https://api.github.com"
        headers = {"Authorization": "Bearer " + self.token, "Accept": "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "WardPulse-release"}
        if method == "GET":
            headers["Cache-Control"] = "no-cache"
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
                result = json.load(response)
                if page is not None:
                    return result, self.page_links(response.headers, path.partition("?")[0], page)
                return result
        except urllib.error.HTTPError as error:
            if missing and error.code == 404:
                return NOT_FOUND
            raise

    def page_links(self, headers, path, page):
        links = headers.get_all("Link", [])
        if not links:
            return {}
        category = "pagination-invalid"
        repository = rf"(?:/repos/(?i:{re.escape(self.repository)})|/repositories/{self.repository_id})"
        endpoint = rf"https://api\.github\.com{repository}{re.escape(path)}"
        number = r"([1-9][0-9]{0,8})"
        query = rf"(?:per_page=100&page={number}|page={number}&per_page=100)"
        pattern = re.compile(rf'<{endpoint}\?{query}>\s*;\s*rel="(first|prev|next|last)"')
        targets = {}
        for header in links:
            for link in header.split(","):
                match = pattern.fullmatch(link.strip())
                require(match is not None, category)
                first_number, second_number, relation = match.groups()
                require(relation not in targets, category)
                targets[relation] = int(first_number or second_number)
        require(targets.get("first", 1) == 1 and targets.get("prev", page - 1) == page - 1, category)
        require(targets.get("next", page + 1) == page + 1, category)
        return targets


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

    def pages(self, operation, path, *, category="validation-failed"):
        seen = set()
        last_page, page_limit = None, 1000
        linked_page = False
        for page in range(1, page_limit + 1):
            items, links = self.request(operation, f"{path}?per_page=100&page={page}", page=page)
            require(type(items) is list and len(items) <= 100, category)
            has_next = "next" in links
            require(items or not (linked_page or has_next), "pagination-invalid")
            advertised_last = links.get("last")
            if advertised_last is not None:
                first_possible_last = page if linked_page else max(1, page - 1)
                require(first_possible_last <= advertised_last <= page_limit
                        and last_page in (None, advertised_last), "pagination-invalid")
                last_page = advertised_last
            if last_page is not None:
                require(has_next == (page < last_page), "pagination-invalid")
                if page > last_page:
                    require(not items, "pagination-invalid")
                    return
            for item in items:
                require(type(item) is dict and type(item.get("id")) is int and item["id"] > 0, category)
                require(item["id"] not in seen, category)
                seen.add(item["id"])
                yield item
            # A full page needs another read even at the advertised end.
            if not has_next and len(items) < 100:
                return
            linked_page = has_next
        raise ValidationError(category)

    def binding(self, release, release_id, draft, *, category="validation-failed"):
        require(type(release) is dict and type(release.get("id")) is int and release["id"] == release_id, category)
        require(release.get("draft") is draft and release.get("prerelease") is self.prerelease, category)
        require(release.get("tag_name") == self.tag and release.get("name") == self.tag, category)
        require(release.get("target_commitish") == self.sha and release.get("body") == self.notes, category)

    def conflicts(self, allowed=None, draft=True):
        listed = False
        for release in self.pages("list-releases", "/releases", category="release-listing-invalid"):
            if release["id"] == allowed:
                self.binding(release, allowed, draft, category="listed-release-binding-mismatch")
                listed = True
            else:
                require(type(release.get("tag_name")) is str, "release-listing-invalid")
                require(release["tag_name"] != self.tag, "conflicting-release")
        return listed

    def tag_binding(self, required=False):
        category = "tag-binding-mismatch"
        ref = self.request("read-tag-ref", "/git/ref/tags/" + urllib.parse.quote(self.tag, safe=""),
                           missing=not required)
        if ref is NOT_FOUND:
            require(not required, category)  # Only a draft may lack a real Git ref.
            return
        require(type(ref) is dict and ref.get("ref") == "refs/tags/" + self.tag, category)
        obj, seen = ref.get("object"), set()
        for _ in range(16):
            require(type(obj) is dict, category)
            target = obj.get("sha")
            require(type(target) is str and re.fullmatch(r"[0-9a-f]{40}", target) and target not in seen, category)
            seen.add(target)
            if obj.get("type") == "commit":
                require(target == self.sha, category)
                return
            require(obj.get("type") == "tag", category)
            annotation = self.request("read-annotated-tag", "/git/tags/" + target)
            require(type(annotation) is dict and annotation.get("sha") == target, category)
            obj = annotation.get("object")
        raise ValidationError(category)

    def observe(self, release_id, draft, *, allow_unlisted=False):
        self.binding(self.request("read-release", f"/releases/{release_id}"), release_id, draft,
                     category="release-by-id-binding-mismatch")
        listed = self.conflicts(release_id, draft)
        require(listed or allow_unlisted, "bound-release-not-listed")
        self.tag_binding(required=not draft)
        return listed

    def observe_created_draft(self, release_id):
        # Allow up to 60 seconds of waiting for the authenticated listing cache to expire.
        for delay in (0, 5, 15, 40):
            if delay:
                sleep(delay)
            if self.observe(release_id, True, allow_unlisted=True):
                return
        raise ValidationError("draft-listing-absent")

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
        self.observe_created_draft(release_id)
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
    elif isinstance(error, ValidationError):
        category = error.category
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
        api = GitHub(env["GH_TOKEN"], env["GITHUB_REPOSITORY"], env["GITHUB_REPOSITORY_ID"])
        publisher = Publisher(api, env["SOURCE_SHA"],
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
