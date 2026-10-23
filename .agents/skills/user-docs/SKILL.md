---
name: user-docs
description: Author and review WardPulse public Vocs user guides, product landing/README copy and UI screenshots. Use when user-visible behaviour or setup changes, or when updating public guidance; keep engineering documentation with its repository owners.
---

# User Documentation — WardPulse

Apply [docs-gate](../docs-gate/SKILL.md) for ownership and currency and
[delegation](../delegation/SKILL.md) for authorship. Delegated authors write plain Markdown
and workflow prose; actual MDX/TS/CSS, scripts and other code are authored only by Runner
execution with independent review. This skill changes no check or commit authority.

## Public audience and owners

Before authoring or reviewing any public guide, landing page, README or route, read the
complete [public-writing rules](references/public-writing.md). Write for installed-app users,
use concise concrete language without AI boilerplate, and keep engineering internals private.

## Accuracy and private review evidence

Apply [accuracy and privacy](references/public-writing.md#accuracy-and-private-review-evidence)
from the same reference to every public claim. Verify actual UI and source evidence; do not
invent successful setup, release acceptance or privacy guarantees.

## Screenshot contract

Before capturing, selecting, presenting or reviewing screenshots, read BOTH complete references:

- [Screenshot format and presentation](references/screenshots.md): shared capture state,
  gallery/task-image scope, names, dimensions, frames, overlays, index and freshness.
- [Capture state](references/capture-state.md): private data, healthy/error examples,
  clean status bars and launchers, rightmost WardPulse dock shortcut, restoration and themes.

These rules apply to guide pages as well as the Overview/README showcase; related captures
must share one application state. Use real UI controls, never retouch app UI to clean a capture.

### Theme matching

Apply [Theme matching](references/capture-state.md#theme-matching) for every screenshot use,
including previews and original links. The phone needs real light/dark captures; the recorded
fixed-dark exception for Wear does not apply to it.

## Final review

Check ALL public pages, menus, direct routes, links and gallery uses against this skill,
not just the last changed paragraph. Independent review and the coordinator's full final
pass must reach ZERO; return findings to the same prose/design author or to Runner for
code fixes, then repeat the whole pass after the last fix.

Keep affected guides, policy, screenshot index and existing workflows current. If none are
affected, give a short reason in the handoff. Existing required validators/build checks
remain mandatory; browser/capture evidence must report what was actually measured and
what remains pending. Do not close unrelated provider, hardware or release acceptance.
