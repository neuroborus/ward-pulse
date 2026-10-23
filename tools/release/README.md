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
owners is read-only after the same configuration, prerelease-state and coherence guards.
With pending normal fragments, it validates their individual product-only ownership through
the official stock plan; a valid future product target need not equal the already prepared
version. Fragments are retained, generation and lock reconciliation do not run, and codes do
not increment. With no pending normal fragment, a fail-closed presence guard permits repeat
success without stock status, which can fail for a changed package after a cut consumes its
fragments. The guard does not parse Markdown or prove semantic coverage. Unsupported inputs
are refused. Status always uses stock planning; needed stock errors remain errors rather than
invented empty plans.

Commands use CLI 3.0.3 offline with lifecycle scripts disabled. CLI and lock commands both
default to npm's configured cache (including `npm_config_cache`); the helper's `--cache PATH`
overrides that selection for both. Run
`python3 tools/release/prepare_release.py --cache PATH status` or replace `status` with
`prepare VERSION`. Missing offline dependencies must be
acquired separately; do not upgrade packages or hand-edit generated files to bypass a failure.

Preparation replaces several files sequentially, not atomically. Generation, lock or I/O
failure preserves partial output and reports that reconciliation is required. Inspect the
ledger, consumed/pending fragments, changelog, lock and all native declarations before
retrying; mixed state refuses further increments. Do not publish, tag, delete evidence or
blindly rerun through uncertain state. The
[version policy](../../docs/product/RELEASE_CHECKLIST.md#release-versions) also requires
checking actual uploaded history separately before distribution.

## HOST acceptance

After Runner DONE and separate ownership retirement, acquire the pinned public CLI separately
from validation. Use npm exec with an isolated, initially empty prefix and cache, even if
the repository already has a local CLI. Installing the package alone can leave npm exec's
cache metadata unavailable to the isolated offline integration:

```bash
release_cache=$(mktemp -d)
release_prefix=$(mktemp -d)
npm exec --prefix "$release_prefix" --cache "$release_cache" \
  --registry=https://registry.npmjs.org --ignore-scripts --yes \
  --package=@changesets/cli@3.0.3 -- changeset --version
```

Then validate offline using that same cache, from the repository root:

```bash
npm_config_cache="$release_cache" \
python3 -m unittest discover -s tools/release -p 'test_*.py'
```

Remove the two temporary directories after acceptance. Alternatively, select an already
populated public cache with `npm_config_cache=PATH` for ordinary offline tests, or omit it to
use npm's configured/default cache. No historical task directory is required. A root
`npm exec` version response may use the local CLI and does not prove cache population; the
isolated stock integration after acquisition is the proof. Tests never acquire dependencies,
copy installations or silently switch caches.

Injected unit contracts cover ownership, preflight, bounded allocation, formatting,
idempotence, literal exact-version notes and preserved partial failures. The stock integration
test uses minimal isolated temporary Git/workspace/native data; it actually reproduces
discovery, bootstrap, changelog and lock generation, then exercises immediate no-fragment
repetition, retained future fragments and foreign-fragment refusal without writes or changes
to real native sources. Its lock asserts CLI version and registry integrity. It needs Node/npm,
Git and the selected populated cache; missing prerequisites fail rather than skip. Measure
warm runtime separately from dependency/build setup. Independent skill evaluation must use raw
partial/complete coverage cases without seeding the expected answer. Required operator gates
also include `actionlint .github/workflows/*.yml`, `just check-doc-citations`,
`git diff --check HEAD`, `just check-docs`, and the local skill validator for `prepare-release`
documented in [AGENTS.md](../../AGENTS.md#required-checks). Record actual outcomes and any
unexecuted gates; Source review is not a runtime pass.
Injected publisher tests also cover state options, draft staging before publication, exact
notes/identity/assets, conflicts, tag peeling and preservation of uncertain effects.

## Initial candidate

The Owner selected one complete unpublished initial `0.1.0`, covering the repository-wide
candidate through `f7da9b3` and the release tooling added after `54f9b2e`. On 2026-10-23,
Root verified that GitHub release `421214319` for `v0.1.0` was a draft with no publication
timestamp, deleted that exact draft and observed an empty release list. No `v0.1.0` tag
existed. These observations do not establish Google Play upload or delivery history.

To correct the incomplete initial notes, the verified unpublished ledger input was reset
to `0.0.0` and the incomplete changelog removed. A standard initial minor fragment supplied
candidate coverage; the existing tooling patch retained its meaningful notes. Actual stock
Changesets CLI 3.0.3 generated one complete `0.1.0` manifest/changelog and consumed both
fragments. The existing workspace lock already matched the resulting version, so no lock
reconciliation was needed. Generated output was not edited by hand.

All four Android versionNames remain `0.1.0`, with phone/Wear/legacy/Push codes `1/2/1/1`;
their source files are unchanged. This was unpublished ledger regeneration, without a native
version transition. Root/docs remain `0.0.0`; Cargo and Dart metadata are independent.
Local preparation, generated notes, a tag alone or a draft do not prove publication. Verify
actual publication records before correcting an initial candidate; preserve published
notes, tags and delivered artifacts. Conflicting publication evidence requires stopping and
reporting the finding, not rewriting history. Meaningful tooling notes belong in an explicitly
selected unpublished initial version rather than forcing its first publication to `0.1.1`.

## Publication boundary

Follow the [release checklist](../../docs/product/RELEASE_CHECKLIST.md) for signing,
artifact verification and the independent manual GitHub and Google Play workflows. Local
release preparation does not authorize remote mutations, tags, credentials or publication.
The [Google Play owner](../release-google-play/README.md) retains its historical published
artifact contract.

The GitHub workflow defaults to `draft=true`, `prerelease=false`, `latest=false`. Draft and
prerelease are independent markers; tags remain stable `vMAJOR.MINOR.PATCH`. Latest accepts
`true`, `false` or `automatic`; `true` requires a published normal release. Automatic requests
GitHub's `legacy` policy only for a published normal release and requests nonlatest otherwise.

Before build setup, `prepare_release.py readiness TAG` checks ledger/tag/native agreement,
nonempty exact-version generated notes and absence of pending Changesets input, without npm.
It reads Markdown literally from the original immutable dispatch checkout. This fail-closed
presence guard checks source readiness; it does not prove semantic coverage or publication.
Development status still permits pending fragments and retains actual stock errors, including
the changed-package/no-fragment error after a cut. The complete unpublished initial `0.1.0`
entry includes the tooling notes with no pending normal fragment; a later version cut is not
a prerequisite for its first publication. Fresh acceptance and an authorized manual dispatch
remain separate from preparation.

[`release_github.py`](release_github.py) is the single publisher, downstream of the independent
nine-file receipt verifier. It refuses every existing matching release, including drafts,
and repeatedly checks conflicts and tag refs. It always creates a nonlatest draft with the
exact notes and prerelease marker, uploads and verifies all nine asset identities/sizes and
supplied digests, then applies any requested publication transition only to its newly created
bound ID. The final PATCH explicitly resends the verified tag, full source SHA, name and exact
literal Changesets body with the selected state markers and latest policy, so binding does
not depend on omitted-field preservation. Notes remain untrusted data. Response and fresh
final observations check identity, tag, source, name, body, markers and assets; public releases
require a real tag ref peeled to the source. Latest is a request policy, not an echoed Release field.
Failures preserve partial or public state for Owner reconciliation without retry, overwrite,
resume, deletion or tag movement. If draft was selected, inspect and manually publish it
before Play; Play continues to require a published normal release, including historical
sources without this ledger. Hosted new-mode acceptance remains pending.
