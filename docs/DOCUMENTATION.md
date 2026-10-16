# Documentation Workflow

WardPulse uses Vocs for public user documentation while keeping authoritative Markdown
close to its owners. Engineering, design, toolchain and contributor references remain in
the repository, indexed by `docs/README.md`, outside the public user site. Apply
[user-docs](../.agents/skills/user-docs/SKILL.md) for the public audience and screenshot rules.

## Ownership

- Shared product and engineering knowledge belongs in `docs/`.
- Product, provider, security, and release guidance belongs in `docs/product/`.
- Installed-app user guidance belongs in `docs/product/user-guide/`; public UI PNGs and their
  index belong in `docs/assets/`.
- Application, binding, and tool guidance belongs in the nearest `README.md`.
- `docs/site/` owns the public user-documentation Vocs configuration, navigation and presentation adapters.

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

## Publish through GitHub Pages

The [Docs workflow](../.github/workflows/docs.yml) builds the user site for
<https://neuroborus.github.io/ward-pulse/> using `WARDPULSE_DOCS_BASE_PATH=/ward-pulse`.
It retains main-targeted pull-request validation for documentation, component READMEs,
npm/runtime files and the workflow itself. Automatic publication runs only on pushes to
`main` that include `docs/**` changes. Updates on other branches or without `docs/**`
changes do not automatically publish, including changes limited to application code,
workflow files or root npm files.

The build job uses the pinned Node runtime and runs these commands from the repository root:

```sh
npm ci
python3 tools/check-doc-citations.py
WARDPULSE_DOCS_BASE_PATH=/ward-pulse npm run docs:build
```

Only push or manual `workflow_dispatch` runs on `refs/heads/main` upload the static
`docs/site/dist/public` directory and deploy it. Pull requests and manual runs on other refs
build without publishing. Pages configuration and write permissions belong to the deploy
job, which depends on the successful build and uses the `github-pages` environment. Its
`pages` concurrency group serializes deployments without cancelling an active deployment;
pull-request checks remain outside that group.

Before the first deployment, if Pages is not configured for Actions, an administrator must
select **Settings → Pages → Build and deployment → Source → GitHub Actions**. Repository
Actions policy must allow the workflow and its official Pages actions. If the `github-pages`
environment has branch restrictions or required approvals, allow `main` and satisfy those
rules. The workflow does not enable Pages or change repository settings.

The manual **Run workflow** control becomes available under **Actions → Docs** only after
the updated workflow reaches the default branch, `main`. Choose `main` to deploy manually;
no documentation diff is required. The public site becomes available after a successful
deployment. Confirm the deployment URL and actual site before reporting publication.

## Publish a prefixed static site

Unset or empty `WARDPULSE_DOCS_BASE_PATH` keeps the default local `/` build. The only
supported prefixes are `/ward-pulse` for GitHub Pages and `/wardpulse-docs` for local sharing.
To serve the site under `/wardpulse-docs`, run the default required checks, including
`just check-docs`, before the final prefix build. From the repository root:

```sh
WARDPULSE_DOCS_BASE_PATH=/wardpulse-docs npm run docs:build
```

Expose exactly the generated `docs/site/dist/public` directory through the installed
cloudflared MCP alias `expose_files`, with key `wardpulse-docs`, `url_mode` set to `path`
and live exposure. Do not expose source or a parent output directory. While this output is
exposed live, do not overwrite it with a default build or `just check-docs`.

Verify the returned public prefix: open the homepage and guide/privacy routes, use navigation
and direct anchors, and check matching-theme previews and original images. Check native
**Skip to content** by keyboard after both direct entry and client navigation. A successful
local prefix build is not remote publication/browser acceptance; report only what was
actually verified. This workflow leaves provider, hardware and release acceptance unchanged.

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
3. Add a thin page under `docs/site/src/pages/` only for public user guidance or relevant privacy/help.
4. Update `docs/site/vocs.config.ts` when site navigation changes.
5. Run `just check-docs` and fix unstable source citations or MDX errors; review local links.

Prefer Markdown for prose. Use MDX only when a page needs imports or Vocs components.
