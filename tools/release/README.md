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
official release plan and native state from the repository root:

```bash
just release-status
```

Status reports pending fragments; it does not audit their semantic coverage. Resolve the
requested baseline/range and inspect actual changes across the whole repository, including
apps and core, against both pending fragments and generated notes. Stock `--since` detects
changed package directories and can miss product changes outside `tools/release`. Supply
meaningful missing notes with a justified bump; complete coverage needs no extra fragment.
The [prepare-release skill](../../.agents/skills/prepare-release/SKILL.md) owns this audit.
The helper validates each fragment's targets in stock `status --output` JSON, including
fragments excluded from an aggregate product bump. It does not parse fragment Markdown.

## Local version preparation

For an explicitly requested stable cut, run `just prepare-release VERSION`. The stdlib
[`prepare_release.py`](prepare_release.py) owner checks the selected target against the
official stock plan. Before stock generation or native writes it validates product-only
fragment targets, the ledger/configuration, coherent unambiguous native declarations, odd
phone/next even Wear allocation and positive 32-bit bounds, including the complete next
allocation. Mixed versions, rollback, unsafe declaration forms and overflow fail preflight.

For a genuine transition, stock `changeset version` changes the ledger, generates notes and
consumes fragments; actual npm reconciles the workspace lock. The bridge then mirrors the
target into only the four Android versionNames, advancing phone by 2, Wear to the next even
code, and legacy/Push independently by 1. Formatting and non-version content are retained;
Cargo and Dart metadata are independent. A target already matching the ledger and all native
owners is a no-op, retaining pending fragments without running generation or incrementing codes.
Status permits pending fragments and makes no Source changes; stock's missing-changeset or
comparison-ref errors remain errors rather than invented empty plans.

Commands use CLI 3.0.3 offline with lifecycle scripts disabled. For an explicit public cache,
use `python3 tools/release/prepare_release.py --cache PATH status` or replace `status` with
`prepare VERSION`. Missing offline dependencies must be acquired through the supported
dependency route; do not upgrade packages or hand-edit generated files to bypass a failure.

Preparation replaces several files sequentially, not atomically. Generation, lock or I/O
failure preserves partial output and reports that reconciliation is required. Inspect the
ledger, consumed/pending fragments, changelog, lock and all native declarations before
retrying; mixed state refuses further increments. Do not publish, tag, delete evidence or
blindly rerun through uncertain state. The
[version policy](../../docs/product/RELEASE_CHECKLIST.md#release-versions) also requires
checking actual uploaded history separately before distribution.

## HOST acceptance

After Runner DONE and separate ownership retirement, run:

```bash
python3 -m unittest discover -s tools/release -p 'test_*.py'
```

Injected unit contracts cover ownership, preflight, bounded allocation, formatting,
idempotence, literal exact-version notes and preserved partial failures. The stock integration
test uses minimal isolated temporary Git/workspace/native data and the pinned public cache at
`LOCAL_ARTIFACTS/changesets-release-2026-10-23/npm-cache`; it actually reproduces discovery,
bootstrap, changelog and lock generation, then exercises future transitions without touching
real native sources. Its lock asserts CLI version and registry integrity. It needs Node/npm,
Git and that populated cache; missing prerequisites fail rather than skip. Measure warm
runtime separately from dependency/build setup. Independent skill evaluation must use raw
partial/complete coverage cases without seeding the expected answer. Runtime and full docs
acceptance remain pending until HOST executes them; Source review is not a runtime pass.

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
