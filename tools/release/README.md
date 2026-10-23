# WardPulse release preparation

## Product ledger

[`package.json`](package.json) is the single private logical product, `@wardpulse/app`, for
the phone, Rust core, Wear OS and watch face. It is an explicit root npm workspace.
The root tooling package and `docs/site` workspace remain private at `0.0.0`; neither owns
the product version. Cargo package versions and Dart binding metadata remain independent.

Stock Changesets CLI **3.0.3** owns release planning, version changes, adjacent
[`CHANGELOG.md`](CHANGELOG.md) generation and fragment consumption. Standard fragments and
their coverage rules live in [`.changeset`](../../.changeset/README.md). Only
`@wardpulse/app` may be targeted by release fragments. Private status and workspace discovery
alone do not enforce that policy.

The [configuration](../../.changeset/config.json) uses the stock changelog generator and
`main` comparison baseline, versions private packages, disables private-package tags and
automatic commits, and has no ignored packages. Global release tags remain a manual Owner
operation. There is no npm publication step.

## Stock commands and coverage

After installing the pinned root dependencies with `npm ci --ignore-scripts`, inspect the
official release plan from the repository root:

```bash
npm exec -- changeset status
```

Status reports pending fragments; it does not audit their semantic coverage. Resolve the
requested baseline/range and inspect actual changes across the whole repository, including
apps and core, against both pending fragments and generated notes. Stock `--since` detects
changed package directories and can miss product changes outside `tools/release`. Supply
meaningful missing notes with a justified bump; complete coverage needs no extra fragment.

An explicitly requested version cut uses stock `changeset version` to update the ledger,
generate notes and consume fragments. This command writes Source; status does not. Native
versions and codes must be prepared coherently under the
[release version policy](../../docs/product/RELEASE_CHECKLIST.md#release-versions). Do not
publish, tag or treat a partial preparation as ready. Preserve unexpected partial output
for reconciliation rather than silently retrying or incrementing again.

## Initial candidate

The ledger was bootstrapped from `0.0.0` with an initial minor fragment. Actual stock
`changeset version` generated the `0.1.0` manifest/changelog and consumed that fragment;
actual npm lock generation reconciled workspace metadata. The standard configuration and
fragment were authored directly, without claiming an interactive `init` generated them.

The initial entry records only existing candidate features. All four Android versionNames
remain `0.1.0`, with phone/Wear/legacy/Push codes `1/2/1/1`. As recorded on 2026-10-23, the
existing GitHub release was a draft, not evidence of public publication. Bootstrap does
not authorize publication or change native, Cargo or Dart versions.

## Publication boundary

Follow the [release checklist](../../docs/product/RELEASE_CHECKLIST.md) for signing,
artifact verification and the independent manual GitHub and Google Play workflows. Local
release preparation does not authorize remote mutations, tags, credentials or publication.
The [Google Play owner](../release-google-play/README.md) retains its historical published
artifact contract.
