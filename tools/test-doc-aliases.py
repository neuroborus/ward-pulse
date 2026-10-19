#!/usr/bin/env python3
"""Check compatibility aliases in built Docs HTML, after either deployment-base build."""

from __future__ import annotations

import argparse
import re
import unittest
from collections import Counter
from dataclasses import dataclass, field
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ROOT / "docs/site/dist/public"
HEADINGS = {
    "providers": (
        "connect-providers", "cursor-browser-fallback", "check-the-connection",
        "reconnect-change-or-remove-a-connection", "budget-limits-and-alert-thresholds",
        "keep-credentials-private",
    ),
    "providers-cursor": (
        "cursor", "cursor-plan", "advanced-paste", "chrome", "firefox", "safari", "save-the-token",
        "team-admin-api", "before-unify", "create-a-team", "create-a-team-key",
        "connect-the-key", "read-the-history", "reconnect-change-or-remove-a-connection",
    ),
}
TABLE_ALIASES = (
    "codex-subscription", "claude-subscription", "cursor-plan",
    "openai-platform-reporting", "anthropic-organization-reporting", "cursor-team-admin-api",
)
BROWSER_ALIASES = ("chrome", "firefox", "safari", "save-the-token")


@dataclass(eq=False)
class Element:
    tag: str
    attrs: dict[str, str | None]
    parent: Element | None = None
    children: list[Element | str] = field(default_factory=list)

    def text(self) -> str:
        return "".join(child.text() if isinstance(child, Element) else child
                       for child in self.children)

    def ancestors(self):
        node = self.parent
        while node:
            yield node
            node = node.parent


class Page(HTMLParser):
    def __init__(self, route: str):
        super().__init__(convert_charrefs=True)
        self.elements: list[Element] = []
        self.stack = [Element("document", {})]
        self.feed((PUBLIC / route / "index.html").read_text(encoding="utf-8"))
        self.close()

    def handle_starttag(self, tag, attrs):
        element = Element(tag, dict(attrs), self.stack[-1])
        self.stack[-1].children.append(element)
        self.elements.append(element)
        if tag not in {"area", "base", "br", "col", "embed", "hr", "img", "input",
                       "link", "meta", "param", "source", "track", "wbr"}:
            self.stack.append(element)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_endtag(self, tag):
        for index in range(len(self.stack) - 1, 0, -1):
            if self.stack[index].tag == tag:
                del self.stack[index:]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(data)

    def section(self, element: Element) -> str | None:
        return next((node.attrs.get("id")
                     for node in reversed(self.elements[:self.elements.index(element)])
                     if node.tag in {"h1", "h2", "h3", "h4", "h5", "h6"}), None)


class RenderedAliasesTest(unittest.TestCase):
    base_prefix = ""

    @classmethod
    def setUpClass(cls):
        cls.pages = {f"/guide/{name}": Page(f"guide/{name}") for name in (
            "providers", "providers-cursor", "providers-openai", "providers-anthropic",
            "troubleshooting",
        )}

    def element_with_id(self, page: Page, alias: str) -> Element:
        matches = [node for node in page.elements if node.attrs.get("id") == alias]
        self.assertEqual(len(matches), 1, f"Expected one rendered element with id={alias}")
        return matches[0]

    def check_alias(self, name: str, alias: str, ancestor: str, section: str | None = None):
        page = self.pages[f"/guide/{name}"]
        span = self.element_with_id(page, alias)
        self.assertEqual(span.tag, "span")
        self.assertTrue(any("data-v-content" in node.attrs for node in span.ancestors()))
        self.assertTrue(any(node.tag == ancestor for node in span.ancestors()))
        if section:
            self.assertEqual(page.section(span), section)

        # Derive labels from the owner instead of freezing a second copy of public prose.
        owner = ROOT / "docs/product/user-guide" / f"{name.upper().replace('-', '_')}.md"
        markers = re.findall(rf'<span id="{re.escape(alias)}">(.*?)</span>',
                             owner.read_text(encoding="utf-8"), re.DOTALL)
        self.assertEqual(len(markers), 1)
        link = re.fullmatch(r"\[([^\]]+)\]\(([^)]+)\)", markers[0])
        strong = re.fullmatch(r"\*\*(.+?)\*\*", markers[0], re.DOTALL)
        self.assertTrue(link or strong, f"Unexpected alias content: {alias}")
        expected_text = unescape((link or strong).group(1))
        self.assertTrue(expected_text.strip())
        self.assertEqual(" ".join(span.text().split()), " ".join(expected_text.split()))

        content = [node for node in page.elements if node.parent is span]
        self.assertEqual(len(content), 1)
        self.assertEqual(content[0].tag, "a" if link else "strong")
        if link:
            self.assertEqual(content[0].attrs.get("href"), self.base_prefix + link.group(2))
            destination = urlsplit(link.group(2))
            target = self.element_with_id(self.pages[destination.path], destination.fragment)
            self.assertIn(target.tag, {"h2", "h3"})

    def test_meaningful_rendered_aliases(self):
        for alias in TABLE_ALIASES:
            with self.subTest(alias=alias):
                self.check_alias("providers", alias, "td")
        for alias in BROWSER_ALIASES:
            with self.subTest(alias=alias):
                self.check_alias("providers", alias, "p", "cursor-browser-fallback")
        self.check_alias("providers-cursor", "create-team", "li", "create-a-team")
        self.check_alias("providers-cursor", "team-key-permissions", "p", "create-a-team-key")

    def test_unique_ids_and_ordinary_heading_slugs(self):
        for route, page in self.pages.items():
            with self.subTest(route=route):
                counts = Counter(node.attrs["id"] for node in page.elements if node.attrs.get("id"))
                self.assertEqual({key: count for key, count in counts.items() if count > 1}, {})
        for name, slugs in HEADINGS.items():
            for slug in slugs:
                with self.subTest(page=name, slug=slug):
                    heading = self.element_with_id(self.pages[f"/guide/{name}"], slug)
                    self.assertIn(heading.tag, {"h1", "h2", "h3"})

    def test_troubleshooting_permission_link(self):
        href = self.base_prefix + "/guide/providers-cursor#team-key-permissions"
        self.assertTrue(any(node.tag == "a" and node.attrs.get("href") == href
                            for node in self.pages["/guide/troubleshooting"].elements))
        self.element_with_id(self.pages["/guide/providers-cursor"], "team-key-permissions")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-path", choices=("/", "/ward-pulse", "/wardpulse-docs"), default="/")
    RenderedAliasesTest.base_prefix = parser.parse_args().base_path.rstrip("/")
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(RenderedAliasesTest)
    raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
