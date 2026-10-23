#!/usr/bin/env python3
"""Inspect the stock release plan or explicitly prepare one stable product version."""

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess
import tempfile


PRODUCT = "@wardpulse/app"
CLI_VERSION = "3.0.3"
MAX_CODE = 2**31 - 1
SOURCES = {
    "phone": "apps/phone_flutter/pubspec.yaml",
    "wear": "apps/wear_android/app/build.gradle.kts",
    "legacy": "apps/watchface_wff/build.gradle.kts",
    "push": "apps/wear_android/watchface_push/build.gradle.kts",
}


def stable(version):
    if not isinstance(version, str) or not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("Expected a stable MAJOR.MINOR.PATCH version")
    parts = tuple(map(int, version.split(".")))
    if any(part > 2**53 - 1 for part in parts):
        raise ValueError("Version exceeds the stock semver integer bound")
    return parts


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def ledger(root):
    manifest = read_json(root / "tools/release/package.json")
    if manifest.get("name") != PRODUCT or manifest.get("private") is not True:
        raise ValueError("Expected the private logical product ledger")
    stable(manifest["version"])
    return manifest["version"]


class Stock:
    def __init__(self, root, cache=None):
        self.root = root
        self.cache_args = [f"--cache={cache}"] if cache else []

    def run(self, args):
        subprocess.run(args, cwd=self.root, check=True)

    def changeset(self, *args):
        self.run(["npm", "exec", "--offline", "--yes", "--ignore-scripts", *self.cache_args,
                  f"--package=@changesets/cli@{CLI_VERSION}", "--", "changeset", *args])

    def plan(self):
        with tempfile.TemporaryDirectory(prefix="wardpulse-release-plan-") as directory:
            output = Path(directory) / "plan.json"
            self.changeset("status", "--output", str(output))
            return read_json(output)

    def version(self):
        self.changeset("version")

    def reconcile_lock(self):
        self.run(["npm", "install", "--package-lock-only", "--offline", "--ignore-scripts", *self.cache_args])


def validate_plan(plan, current):
    if plan.get("preState") is not None:
        raise ValueError("Changesets prerelease mode is not supported")
    fragments = plan["changesets"]
    for fragment in fragments:
        targets = fragment["releases"]
        if targets and (len(targets) != 1 or targets[0]["name"] != PRODUCT
                        or targets[0]["type"] not in ("major", "minor", "patch")):
            raise ValueError(f"Changeset {fragment['id']} must target only {PRODUCT}")
    releases = plan["releases"]
    if not releases:
        if any(fragment["releases"] for fragment in fragments):
            raise ValueError("Product fragments have no official release")
        return current
    if len(releases) != 1 or releases[0]["name"] != PRODUCT:
        raise ValueError("Official plan must release only the logical product")
    release = releases[0]
    target = release["newVersion"]
    if release["oldVersion"] != current or stable(target) <= stable(current):
        raise ValueError("Official plan disagrees with the current stable ledger")
    return target


def validate_config(root):
    config = read_json(root / ".changeset/config.json")
    expected = {"commit": False, "changelog": "@changesets/cli/changelog", "baseBranch": "main",
                "ignore": [], "fixed": [], "linked": [],
                "privatePackages": {"version": True, "tag": False}}
    if any(config.get(key) != value for key, value in expected.items()):
        raise ValueError("Restore the stock product-only configuration before preparation")
    if read_json(root / "package.json").get("devDependencies", {}).get("@changesets/cli") != CLI_VERSION:
        raise ValueError("The root must pin the supported Changesets CLI")


def kotlin_code(text):
    """Mask comments and strings, retaining offsets for declaration replacement."""
    pattern = r'//[^\r\n]*|/\*.*?\*/|""".*?"""|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\''

    def mask(match):
        if match[0].startswith("/*") and "/*" in match[0][2:]:
            raise ValueError("Nested Kotlin comments require declaration review")
        return re.sub(r"[^\r\n]", " ", match[0])

    code = re.sub(pattern, mask, text, flags=re.S)
    if "/*" in code or '"' in code or "'" in code:
        raise ValueError("Unsupported or unterminated Kotlin comment/string")
    return code


def only_match(pattern, text, label):
    matches = list(re.finditer(pattern, text, re.M))
    if len(matches) != 1:
        raise ValueError(f"Expected one unambiguous {label}")
    return matches[0]


@dataclass
class Native:
    path: Path
    original: str
    version: str
    code: int
    version_span: tuple
    code_span: tuple

    def updated(self, version, code):
        result = self.original
        for (start, end), value in sorted([(self.version_span, version), (self.code_span, str(code))], reverse=True):
            result = result[:start] + value + result[end:]
        return result


def native(root, name):
    path = root / SOURCES[name]
    if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError(f"Native source must be a regular owned file: {path}")
    text = path.read_bytes().decode("utf-8")
    if name == "phone":
        only_match(r'''^[ \t]*(?:version|"version"|'version')[ \t]*:''', text, "phone version key")
        match = only_match(r"^version:[ \t]*(?P<version>[0-9.]+)\+(?P<code>[0-9]+)[ \t]*(?:#[^\r\n]*)?\r?$", text, "phone version")
        version_span, code_span = match.span("version"), match.span("code")
    else:
        code = kotlin_code(text)
        block = only_match(r"\bdefaultConfig\b", code, f"{name} defaultConfig")
        opening = re.match(r"\s*\{", code[block.end():])
        if not opening:
            raise ValueError("Unsupported defaultConfig form")
        start = block.end() + opening.end()
        version_token = only_match(r"(?<![\w.])versionName\b", code, f"{name} versionName")
        code_token = only_match(r"(?<![\w.])versionCode\b", code, f"{name} versionCode")
        for token in (version_token, code_token):
            between = code[start:token.start()]
            if token.start() < start or between.count("{") != between.count("}") or "}" in between:
                raise ValueError("Version declarations must be directly inside defaultConfig")
        if re.search(r"\bsetVersion(?:Name|Code)\b", code):
            raise ValueError("Unsupported version setter")
        for field in ("versionName", "versionCode"):
            only_match(r"\b" + field + r"\b\s*(?:[+*/-]?=|\()", code, f"{name} {field} assignment")
        version_match = only_match(r'^\s*versionName[ \t]*=[ \t]*"(?P<version>[0-9.]+)"[ \t]*(?://[^\r\n]*)?\r?$', text, f"{name} versionName literal")
        version_span = version_match.span("version")
        rhs = r"pushVersionCode\.get\(\)" if name == "push" else r"(?P<code>[0-9]+)"
        match = only_match(r"^\s*versionCode[ \t]*=[ \t]*" + rhs + r"[ \t]*(?://[^\r\n]*)?\r?$", text, f"{name} versionCode literal")
        if not (version_match.start() <= version_token.start() < version_match.end()
                and match.start() <= code_token.start() < match.end()):
            raise ValueError("Literal declarations disagree with active Kotlin code")
        if name == "push":
            if len(re.findall(r"\bpushVersionCode\b", code)) != 2:
                raise ValueError("Unsupported Push code declaration or override")
            match = only_match(
                r'\bval pushVersionCode\s*=\s*providers\.gradleProperty\("wardpulsePushVersionCode"\)\.map\s*\{\s*value ->\s*'
                r'value\.toIntOrNull\(\)\?\.takeIf\s*\{\s*it > 0\s*\}\s*'
                r'\?: throw GradleException\("wardpulsePushVersionCode must be a positive integer\."\)\s*'
                r'\}\.orElse\((?P<code>[0-9]+)\)[ \t]*\r?$', text, "guarded Push code default")
            declaration = only_match(r"\bval\s+pushVersionCode\b", code, "active Push code default")
            if declaration.start() != match.start():
                raise ValueError("Guarded Push default is not the active declaration")
        code_span = match.span("code")
    version = text[slice(*version_span)]
    stable(version)
    raw_code = text[slice(*code_span)]
    if not re.fullmatch(r"[1-9][0-9]*", raw_code) or int(raw_code) > MAX_CODE:
        raise ValueError(f"{name} code must be a positive 32-bit integer")
    return Native(path, text, version, int(raw_code), version_span, code_span)


def native_state(root, current):
    sources = {name: native(root, name) for name in SOURCES}
    if any(source.version != current for source in sources.values()):
        raise ValueError("Mixed native/ledger versions; reconcile the preserved state before retrying")
    if sources["phone"].code % 2 != 1 or sources["wear"].code != sources["phone"].code + 1:
        raise ValueError("Expected the odd phone / next even Wear allocation")
    return sources


def release_notes(root, version):
    stable(version)
    text = (root / "tools/release/CHANGELOG.md").read_text(encoding="utf-8")
    sections, selected, fence = [], None, None
    for line in text.splitlines(keepends=True):
        marker = re.match(r" {0,3}(`{3,}|~{3,})(.*)", line)
        if fence:
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= len(fence) and not marker[2].strip():
                fence = None
        elif marker:
            fence = marker[1]
        elif line.startswith("## "):
            selected = [] if line.strip() == f"## {version}" else None
            if selected is not None:
                sections.append(selected)
            continue
        if selected is not None:
            selected.append(line)
    if len(sections) != 1 or not any(line.strip() and not line.lstrip().startswith("#") for line in sections[0]):
        raise ValueError(f"Missing, empty or duplicate generated notes for {version}")
    return "".join(sections[0]).strip()


def readiness(root, tag):
    """Read an already prepared immutable release without npm or fragment parsing."""
    if not isinstance(tag, str) or not tag.startswith("v"):
        raise ValueError("Expected a stable vMAJOR.MINOR.PATCH tag")
    version = tag[1:]
    stable(version)
    validate_config(root)
    if ledger(root) != version:
        raise ValueError("Tag differs from the prepared product ledger")
    sources = native_state(root, version)
    # Fail closed on all extra inputs, including normal fragments and pre-mode state.
    # This presence guard is not a semantic coverage audit.
    if any(path.name not in ("config.json", "README.md") for path in (root / ".changeset").iterdir()):
        raise ValueError("Pending Changesets input; prepare the immutable release before publication")
    return {"version": version, "codes": {name: item.code for name, item in sources.items()},
            "notes": release_notes(root, version)}


def status(root, stock):
    validate_config(root)
    current = ledger(root)
    sources = native_state(root, current)
    plan = stock.plan()
    target = validate_plan(plan, current)
    return {"current": current, "target": target, "codes": {name: item.code for name, item in sources.items()}, "plan": plan}


def prepare(root, target, stock):
    stable(target)
    validate_config(root)
    current = ledger(root)
    sources = native_state(root, current)
    if stable(target) < stable(current):
        raise ValueError("Refusing a version rollback")
    if target == current:
        return False
    plan = stock.plan()
    if validate_plan(plan, current) != target:
        raise ValueError("Requested target differs from the official selected release plan")
    codes = {"phone": sources["phone"].code + 2, "wear": sources["phone"].code + 3,
             "legacy": sources["legacy"].code + 1, "push": sources["push"].code + 1}
    if any(not 0 < code <= MAX_CODE for code in codes.values()):
        raise ValueError("Native versionCode allocation overflows a positive 32-bit integer")
    updates = {name: source.updated(target, codes[name]) for name, source in sources.items()}
    try:
        stock.version()
        if ledger(root) != target:
            raise ValueError("Stock generation did not produce the selected target")
        if any((root / ".changeset" / (fragment["id"] + ".md")).exists() for fragment in plan["changesets"]):
            raise ValueError("Stock generation left selected fragments unconsumed")
        release_notes(root, target)
        stock.reconcile_lock()
        if read_json(root / "package-lock.json")["packages"]["tools/release"]["version"] != target:
            raise ValueError("npm did not reconcile the product workspace lock metadata")
        for source in sources.values():
            if source.path.read_bytes() != source.original.encode("utf-8"):
                raise ValueError("Native source changed during stock generation")
        for name, source in sources.items():
            source.path.write_bytes(updates[name].encode("utf-8"))
    except (Exception, KeyboardInterrupt) as error:
        raise RuntimeError("Preparation may be partial; output is preserved. Reconcile ledger, fragments, "
                           "changelog, lock and all four native sources before retrying. " + str(error)) from error
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--cache", type=Path, help="Public npm cache for offline stock commands")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    cut = commands.add_parser("prepare")
    cut.add_argument("version")
    ready = commands.add_parser("readiness", help="Read prepared version/notes without running npm")
    ready.add_argument("tag")
    args = parser.parse_args()
    stock = Stock(args.root, args.cache)
    try:
        if args.command == "status":
            print(json.dumps(status(args.root, stock), indent=2))
        elif args.command == "readiness":
            print(json.dumps(readiness(args.root, args.tag), indent=2))
        else:
            print("Prepared " + args.version if prepare(args.root, args.version, stock) else "Already prepared; no files changed")
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
