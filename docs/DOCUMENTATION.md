# Documentation Workflow

WardPulse uses Vocs to present repository documentation while keeping Markdown files close to
their owners.

## Ownership

- Shared product and engineering knowledge belongs in `docs/`.
- Product, provider, security, and release guidance belongs in `docs/product/`.
- Application, binding, and tool guidance belongs in the nearest `README.md`.
- `docs/site/` owns only the Vocs configuration, navigation, and presentation adapters.

Vocs pages import authoritative Markdown files. Do not copy their content into the site.

## Toolchain

The documentation workspace uses Node.js 24.18.0, npm 11.16.0, Vocs 2.8.0, Waku
1.0.0-beta.8, and Vite 8.2.0. `.nvmrc` pins Node.js, `packageManager` pins npm, and exact
dependency versions are recorded in `package-lock.json`.

`build.mjs` resolves two Vocs internal module paths to drop the unused OpenAPI UI. They are
not public API, so re-run `just check-docs` after any Vocs upgrade: if the paths move, the
chunk-budget guard fails the build rather than shipping the larger bundle silently.

With nvm, select the repository runtime from the project root:

```sh
nvm install
nvm use
```

Then install dependencies:

```sh
npm ci
```

Run the local site at `http://localhost:5173`:

```sh
just docs-dev
```

Check source citations and build the static site:

```sh
just check-docs
```

Preview a successful build with `npm run docs:preview`.

## Stable Source References

Cite a repository file together with a named symbol, function, or recipe. For documentation,
use a section anchor. Avoid `path:line` citations: unrelated edits move line numbers.

`just check-docs` runs the citation gate before the Vocs build. Run the gate alone without
Node, Git, or network access:

```sh
just check-doc-citations
# Equivalent direct command; only Python 3 and the checkout are required.
python3 tools/check-doc-citations.py
```

The checker scans Markdown and MDX throughout the checkout, including root documents,
component documentation, `.agents/skills`, and new untracked files. It prunes local artifacts,
dependency, vendor, generated, build, coverage, cache, IDE, and VCS directories and does not
follow symlinked files or directories. The exact directory names are in
`EXCLUDED_DIRECTORIES` in `tools/check-doc-citations.py`.

It rejects line, line-range, and line-column suffixes on available checkout files, resolving
repository-root, document-relative, absolute, and bare-filename references. Clock values,
ratios, external URLs, and citations to files outside the checkout remain valid. Diagnostics
name the document, line, offending citation, and stable replacement. Run parsing and discovery
regressions with `just test-doc-citations`; they also run in `just test-all`.

Plain path existence is intentionally not linted: historical references to retired assets and
planned paths can legitimately name absent files, and free-form prose does not encode that
intent reliably. Review those references when a file is renamed or removed.

## Updating Documentation

1. Edit the authoritative Markdown file under `docs/` or beside its owning component.
2. For a new durable document, link it from `docs/README.md`.
3. Add a thin page under `docs/site/src/pages/` when the document should appear on the site.
4. Update `docs/site/vocs.config.ts` when site navigation changes.
5. Run `just check-docs` and fix unstable source citations or MDX errors; review local links.

Prefer Markdown for prose. Use MDX only when a page needs imports or Vocs components.
