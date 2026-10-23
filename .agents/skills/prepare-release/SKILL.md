---
name: prepare-release
description: Audit WardPulse release coverage across the repository, supply meaningful missing Changesets notes, and prepare an explicitly requested local product version. Use for release preparation or changeset coverage, not publication.
---

# Prepare a WardPulse release

Use the [release owner](../../../tools/release/README.md) for the ledger, stock commands,
native bridge and recovery; use the [release checklist](../../../docs/product/RELEASE_CHECKLIST.md#release-versions)
for artifact versions and distribution boundaries. Source, fragment and helper changes follow
[delegation](../delegation/SKILL.md). Routine authorized local preparation needs no additional
generic approval prompt. Publishing, tags, credentials and remote mutations remain separate.

Resolve the actual requested baseline/range and included working changes from the request,
repository history and existing release records. Respect explicit Owner version/scope choices
and preserve existing work. If no range was supplied, establish the last relevant prepared
product version/source and explain the selected comparison; do not assume a tag is published.

Inspect the actual repository-wide diff and affected behavior, including apps, core, bindings,
tooling and documentation. Verify implementation before making a release claim. Read pending
standard fragments and the generated changelog sections covering that range. Match each
meaningful change to existing coverage, recording any no-note disposition briefly. Stock
`--since` detects workspace directories and can miss apps/core outside `tools/release`;
fragment presence, file counts and a successful stock status cannot establish semantic coverage.

When coverage is partial, add or update only the missing logical-product notes in standard
`.changeset/*.md` fragments targeting exclusively `@wardpulse/app`. When coverage is complete,
add none. Avoid duplicate baseline features, filler and fabricated behavior. Explain the
semver bump from the actual compatibility/feature/fix impact and the requested scope; do not
silently override an explicit version choice. Fragment format belongs to
[the fragment owner](../../../.changeset/README.md).

Use `just release-status` to inspect the official plan and product-target guards. Cut a version
only when explicitly requested, with `just prepare-release VERSION`; follow the owner's
preflight and partial-state recovery guidance. Coverage work alone does not consume fragments
or advance native codes. Report the range, covered/missing/no-note changes, fragment changes,
bump rationale and actual validation, leaving unexecuted acceptance pending.
