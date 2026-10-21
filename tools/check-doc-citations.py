#!/usr/bin/env python3
"""Reject unstable path:line citations to checkout files in Markdown and MDX.

This gate uses only the Python standard library and never invokes Git, Node,
or the network. Historical and planned prose paths need not exist; only line
citations identifying files available in the checkout are rejected.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from typing import Iterator


ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_DIRECTORIES = {
    ".git", ".hg", ".svn", ".claude", ".toolchains", ".dart_tool",
    ".gradle", ".kotlin", ".cxx", ".cache", ".npm", ".pub-cache",
    ".vocs", ".venv", ".idea", ".idea_modules", ".vscode",
    "LOCAL_ARTIFACTS", "node_modules", "target", "build", "dist",
    "generated", "vendor", "venv", "__pycache__", "coverage", "debug",
    "out", "captures",
}

# Consume URLs first so a remote filename or port cannot become a local citation.
TOKENS = re.compile(
    r"(?P<url>\b[A-Za-z][A-Za-z0-9+.-]*://[^\s<>`\"']+)"
    r"|(?<![\w./:\-])(?P<citation>"
    r"(?P<path>/?(?:[\w.-]+/)*[\w.-]+):"
    r"[0-9]+(?::[0-9]+)?(?:[-–][0-9]+(?::[0-9]+)?)?)(?!\w)"
)


def raise_walk_error(error: OSError) -> None:
    raise error


def repository_files(root: Path) -> Iterator[Path]:
    """Discover source files without reading dependency or generated trees."""
    for directory, directories, filenames in os.walk(
        root, followlinks=False, onerror=raise_walk_error
    ):
        parent = Path(directory)
        directories[:] = sorted(
            name for name in directories
            if name not in EXCLUDED_DIRECTORIES
            and not name.startswith(("cmake-build-", "mutants.out"))
            and not (parent / name).is_symlink()
        )
        for name in sorted(filenames):
            path = parent / name
            if not path.is_symlink() and path.is_file():
                yield path


def is_repository_reference(
    text: str, document: Path, root: Path, files: set[Path], basenames: set[str]
) -> bool:
    # Clocks and ratios remain numbers even if a numeric filename exists.
    if text.isdigit():
        return False
    path = Path(text)
    if path.is_absolute():
        candidates = (path, root / text.lstrip("/"))
    else:
        candidates = (document.parent / path, root / path)
    for candidate in candidates:
        try:
            if candidate.resolve() in files:
                return True
        except RuntimeError:
            # A symlink loop cannot identify a checkout source file.
            continue
    # A basename still identifies checkout files when several owners share it.
    return "/" not in text and text in basenames


def check_repository(root: Path) -> tuple[int, list[str]]:
    root = root.resolve()
    files = set(repository_files(root))
    basenames = {path.name for path in files}
    documents = sorted(path for path in files if path.suffix.lower() in {".md", ".mdx"})
    errors = []
    for document in documents:
        for number, line in enumerate(document.read_text(encoding="utf-8").splitlines(), 1):
            for match in TOKENS.finditer(line):
                if match.group("url") is not None:
                    continue
                if is_repository_reference(match.group("path"), document, root, files, basenames):
                    errors.append(
                        f"{document.relative_to(root).as_posix()}:{number}: "
                        f"{match.group('citation')!r}: unstable source citation; "
                        "use the file plus a named symbol/recipe or a documentation section anchor."
                    )
    return len(documents), errors


def main(root: Path = ROOT) -> int:
    try:
        count, errors = check_repository(root)
    except (OSError, UnicodeError) as error:
        print(f"Documentation citation check failed: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        print(f"Found {len(errors)} unstable source citation(s).", file=sys.stderr)
        return 1
    print(f"Documentation citations: checked {count} Markdown/MDX files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
