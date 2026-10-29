---
name: ui-verification
description: Verify WardPulse UI meaning, native rendering, active artifacts and shared state before visual acceptance. Use again after every demonstrated coordinator UI-verification mistake.
---

# UI verification — WardPulse

Use this skill before declaring a UI defect fixed, a rendered surface correct or a
screenshot group accepted. A test/build pass, plausible review art or remembered screen
does not establish the actual displayed result. Keep acceptance limited to proven cases.

## Read the relevant reference

| Verification need | Reference |
| --- | --- |
| Identify the reported defect and check every selected logical metric | [Semantic and visual checks](references/semantic-checks.md) |
| Distinguish form input, validation error and action visibility | [Form visibility](references/form-visibility.md) |
| Prove which artifacts, bindings and state are actually rendered | [State and artifact identity](references/state-and-artifacts.md) |
| Verify a reported locale/unit defect or explicit unit designation | [Locale and units](references/locale-and-units.md) |
| Correct a demonstrated coordinator verification mistake | [Mistake maintenance](references/mistake-maintenance.md) |

For device operations, use [android-devices](../android-devices/SKILL.md) or
[android-emulators](../android-emulators/SKILL.md). Keep ADB/unlock procedures there.
For public images, use [user-docs](../user-docs/SKILL.md); it owns healthy/error examples,
filled default face cells, shared-state groups, privacy, themes and capture presentation.
Owning Android surface rules and locked designs remain authoritative for product behavior.

## Establish the actual case

Before changing state, record the owner's requested defect, expected result and observed
native result in a small sanitized working artifact. Identify the affected surface,
logical metric/window/pool and case; do not substitute a nearby, more obvious defect.
Preserve the incident inputs and original frame. Separate facts, hypotheses and unknowns.

Map EVERY selected logical metric and pair, including missing or unexpected rendered
items, to its provider family, color, band/position, window/pool, value and status using
actual selected data and the owning contract. Check both halves together. Correct shape,
ring count or one updated number is insufficient when a half belongs to the wrong
family/band. Use the semantic reference before PASS.

## Bind the evidence to the running surface

Distinguish Source, generated resources, built artifact, installed artifact and actual
active renderer/instance with effective data/bindings. Record the relevant identities;
package presence, versionName and static defaults do not establish the active rendition.
Use the state/artifact reference when a retained scene, reordered pair or cached surface
can differ from the producer. Updating the app alone does not prove its face was updated.

Inspect the original native frame after the LAST correction and after restoring temporary
state. Confirm complete visible UI and logical mapping, not just the last failing detail.
Use actual viewport geometry; clipped accessibility bounds are not the physical viewport.
Record actual OS font scale separately from a test-injected layout scale.

## Make only supported claims

Compare matched before/after cases and their artifact/state identities. Keep tests, review
art, native runtime and public captures identified as separate evidence. Do not call an
unseen original frame visually verified or borrow an older build's result for new bytes.
If a required identity, binding, value or visible state is unproved, report that part as
Pending. A healthy fixture used for documentation must not erase the incident or count
as its repair. Never hide a bug by replacing its inputs before acceptance.

During review of native layout/state assertions, verify each guard's phase applicability
against the owning contract: a correct predicate can still impose an unsupported condition
in the wrong phase. Preserve proven boundary requirements separately. Include guards before
image or metrics capture. Require bounded diagnostics joined at the failure point: expected
and actual state, target, phase, system font scale, viewport, items/offsets, padding and motion
as applicable. Retain that trace before the risky guard or in its failure message, without
moving or mutating the observed state. Do not loosen or normalize the assertion, or retry
past its failure merely to collect artifacts. Diagnostic output preserves failure evidence;
it does not establish PASS.

After the last fix, the coordinator repeats the full independent zero-findings pass under
[delegation](../delegation/SKILL.md) and applicable [finalization](../finalization/SKILL.md).
Return code findings to actual Runner execution/review; no implementation fallback.

## Learn from EVERY actual verification mistake

When an owner re-report or new evidence demonstrates that the coordinator's UI conclusion
or verification procedure was wrong, complete a delegated update to this skill's closest
owning reference/procedure before another acceptance claim. Follow mistake maintenance
for each occurrence, including a repeated failure of an existing guard. Preserve a small
nonsecret case artifact, fix the failed decision/procedure, and validate the update.
Use independent forward-testing for substantive changes. Keep the entrypoint short;
improve the relevant rule instead of accumulating a generic checklist or approval flow.
