#!/usr/bin/env python3
"""Filesystem and false-positive regressions for the documentation citation gate."""

from __future__ import annotations

import contextlib
import io
import runpy
import tempfile
import unittest
from pathlib import Path


GATE = runpy.run_path(str(Path(__file__).with_name("check-doc-citations.py")))


class DocumentationCitationsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory(prefix="wardpulse-doc-citations-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name).resolve()
        self.write("tools/render-watchface.mjs", "// Source file.\n")
        self.write("justfile", "default:\n")

    def write(self, name: str, text: str) -> Path:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def check(self) -> tuple[int, list[str]]:
        return GATE["check_repository"](self.root)

    def test_path_forms_ranges_columns_and_diagnostics(self) -> None:
        citations = [
            "tools/render-watchface.mjs:12",
            "../tools/render-watchface.mjs:13",
            "/tools/render-watchface.mjs:14",
            f"{self.root}/tools/render-watchface.mjs:15",
            "render-watchface.mjs:16",
            "justfile:17",
            "tools/render-watchface.mjs:18-21",
            "tools/render-watchface.mjs:22:4",
            "tools/render-watchface.mjs:23–25",
        ]
        self.write("docs/guide.md", "\n".join(f"`{citation}`" for citation in citations))
        count, errors = self.check()
        self.assertEqual(count, 1)
        self.assertEqual(len(errors), len(citations))
        for number, (citation, error) in enumerate(zip(citations, errors), 1):
            self.assertTrue(error.startswith(f"docs/guide.md:{number}: "))
            self.assertIn(repr(citation), error)
            self.assertIn("symbol/recipe", error)
            self.assertIn("section anchor", error)

    def test_markdown_links_mdx_and_code_blocks_are_checked(self) -> None:
        self.write("docs/page.mdx", "[source](../tools/render-watchface.mjs:12)\n")
        self.write("README.md", "```text\njustfile:5\n```\n")
        count, errors = self.check()
        self.assertEqual(count, 2)
        self.assertEqual(len(errors), 2)
        self.assertTrue(errors[0].startswith("README.md:2:"))
        self.assertTrue(errors[1].startswith("docs/page.mdx:1:"))

    def test_clocks_urls_and_external_sources_remain_valid(self) -> None:
        self.write("03", "A numeric filename must not turn a clock into a citation.\n")
        self.write("docs/guide.md", "\n".join([
            "03:24 and 12:24; 1:1; prose range 12:24–13:25.",
            "http://localhost:5173 and tcp:5601.",
            "https://example.com/tools/render-watchface.mjs:12",
            "[external](https://example.com/justfile:52)",
            "sceneElement.xsd:45 belongs to a pinned external validator.",
            "`brand/watchface/preview-face-active-quiet.png` was retired.",
            "future/module.py:12 is not a checkout file.",
            "`rasterize` in `tools/render-watchface.mjs`; `check-docs` in `justfile`.",
        ]))
        self.assertEqual(self.check(), (1, []))

    def test_external_filename_becomes_local_when_present(self) -> None:
        self.write("schemas/sceneElement.xsd", "<schema/>\n")
        self.write("docs/guide.md", "sceneElement.xsd:45\n")
        self.assertEqual(len(self.check()[1]), 1)

    def test_ambiguous_checkout_basename_is_rejected(self) -> None:
        self.write("apps/one/README.md", "One owner.\n")
        self.write("apps/two/README.md", "Two owners.\n")
        self.write("docs/guide.md", "README.md:5\n")
        self.assertEqual(len(self.check()[1]), 1)

    def test_discovery_includes_new_component_docs_and_skills(self) -> None:
        for name in ["README.md", "apps/example/README.md", ".agents/skills/example/SKILL.md"]:
            self.write(name, "justfile:5\n")
        count, errors = self.check()
        self.assertEqual(count, 3)
        self.assertEqual(len(errors), 3)
        self.assertEqual(errors, sorted(errors))
        self.write("docs/new-untracked.MD", "justfile:6\n")
        self.assertEqual(self.check()[0], 4)

    def test_dependency_build_generated_and_scratch_trees_are_pruned(self) -> None:
        for directory in sorted(GATE["EXCLUDED_DIRECTORIES"]) + ["cmake-build-debug", "mutants.out.1"]:
            with self.subTest(directory=directory):
                # Invalid UTF-8 proves excluded files are never opened.
                path = self.root / directory / "nested" / "README.md"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"\xffjustfile:5\n")
        self.write("docs/guide.md", "Use the `default` recipe in `justfile`.\n")
        self.assertEqual(self.check(), (1, []))

    def test_symlinked_documentation_is_not_followed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="wardpulse-doc-external-") as external:
            outside = Path(external)
            (outside / "README.md").write_text("justfile:5\n", encoding="utf-8")
            (self.root / "linked-dir").symlink_to(outside, target_is_directory=True)
            (self.root / "linked.md").symlink_to(outside / "README.md")
            self.write(".agents/skills/example/SKILL.md", "Use the `default` recipe.\n")
            (self.root / ".claude").symlink_to(self.root / ".agents", target_is_directory=True)
            self.assertEqual(self.check(), (1, []))

    def test_cli_status_and_unreadable_document_failure(self) -> None:
        self.write("README.md", "justfile:5\n")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual(GATE["main"](self.root), 1)
        self.assertIn("README.md:1: 'justfile:5'", stderr.getvalue())
        self.write("README.md", "Use the `default` recipe in `justfile`.\n")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(GATE["main"](self.root), 0)
        (self.root / "README.md").write_bytes(b"\xff")
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(GATE["main"](self.root), 1)


if __name__ == "__main__":
    unittest.main()
