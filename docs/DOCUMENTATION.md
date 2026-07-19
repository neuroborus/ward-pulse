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

The documentation workspace uses Node.js 24.18.0, npm 11.16.0, Vocs 2.6.0, Waku
1.0.0-beta.7, and Vite 8.1.5. `.nvmrc` pins Node.js, `packageManager` pins npm, and exact
dependency versions are recorded in `package-lock.json`.

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

Build the static site:

```sh
just check-docs
```

Preview a successful build with `npm run docs:preview`.

## Updating Documentation

1. Edit the authoritative Markdown file under `docs/` or beside its owning component.
2. For a new durable document, link it from `docs/README.md`.
3. Add a thin page under `docs/site/src/pages/` when the document should appear on the site.
4. Update `docs/site/vocs.config.ts` when site navigation changes.
5. Run `just check-docs` and fix broken links or MDX errors.

Prefer Markdown for prose. Use MDX only when a page needs imports or Vocs components.
