# Parallel work and shared ownership

Use when overlapping authorized delegates, review or preparation, or coordinating existing
implementation streams. [Focused commit boundaries](../../finalization/references/commit-boundaries.md)
own implementation order; [Runner operation](runner-operation.md) owns lifecycle/check details.
This reference coordinates those rules; it grants no new code, device or external-action authority.

## Match concurrency to the resource

Useful parallel work includes read-only research, requirements preparation and independent
Source review. Give each assignment a concrete scope, one owner for each writable path and a
separate private output location. Disjoint paths do not override frozen Source/input guards.
Code, tests and executable helpers remain actual Runner execution under the selected mode.
Keep the default sequential implementation/integration boundary; do not start another backlog
feature in the same diff or create a clone/worktree merely to fill a wait. Already-authorized
separate streams retain their own dependencies and focused integration boundaries.

Serialize lifecycle overlaps with an actual shared guard or resource conflict. A lifecycle
that may advance shared Git refs conflicts with another that freezes those refs, including
read-only authoring: linked worktrees share branch/tag/stash refs despite disjoint paths.
Two genuinely read-only lifecycles are not forbidden solely by a shared common directory
when they have no shared mutation, frozen-input, output or lease conflict and actual tool
capabilities/ownership support the overlap. This grants no new parallel-pipeline/worktree authority.
The commit-boundary owner requires external commit/stash/tag/ref writes to serialize against
protected lifecycles. Owning admitted Native commits retain their contract; post-run HOST
acceptance does not become their prerequisite.

Contention follows actual resources, not the number of agents. Assign one operator at a time
to a device/emulator or shared mutable build, capture or output context. A handoff identifies
its current state, outstanding temporary changes and restoration owner, then explicitly releases
custody. Independent targets remain available where their work shares no protected resources.
Keep central continuity ledgers single-writer and private task outputs separate; a completed
note is not permission to overwrite another owner's current state or frozen inputs.

For reused collaboration agents, apply the entrypoint's existing work-request/uptake rule.
Send an actionable scope, allowed effects and output owner; informational delivery and queued
context alone do not establish that the requested work began. Reconcile overlap when an agent
finds it needs another owner's path or resource, rather than silently widening its assignment.

## Overlap review without borrowing acceptance

A read-only Source review may overlap an active writer. Pin the candidate diff's immutable
comparison base; HEAD may advance through an admitted Native commit. Bind the actual bytes
acquired/read for every reviewed file and the whole diff, not only paths or start/end hashes.
Matching endpoints do not prove continuous immutability or exclude a changed-then-reverted
version; report those observation limits. Any change observed during the pass, even reverted,
prevents transferring ZERO. After the last correction, repeat the whole independent final pass
bound to the final candidate bytes and its identified immutable base, not only the last fix.
Source-only review need not await terminal status; mandatory candidate HOST checks do.

Start candidate HOST checks only after its entire owning run is DONE, its foreground CLI has
actually exited where used, all known owned processes are retired and separate fresh public
state confirms idle ownership. Do not run new-candidate checks while its writer is active.
This is the owning candidate's boundary, not a blanket prohibition on unrelated authorized
read-only or device work with independent custody. Preserve the scoped retirement rules in
Runner operation; do not turn an unrelated unreadable process into a global blocker.

## Report the proof that actually exists

Distinguish Source review, agent-reported Native results, operator-executed HOST checks,
installed native rendering and live-provider behavior. Name the candidate, actual outcome and
remaining relevant work; one step or commit does not close a feature's integration boundary.
Source ZERO cannot establish that a required suite passed or that new assertions were reached.
Preserve actual failures and superseding triage; do not relabel an earlier Source review as
executed GREEN or use a later successful different case to erase the failed one.

Keep one cohesive feature boundary with its necessary tests/docs/exports and focused commits,
including deliberate cohesive multi-commit plans when needed. Finish its required acceptance
before adding an unrelated implementation to the coordinating diff. On a blocker, report the
concrete unavailable capability or shared resource, leave its obligation open and continue
independent authorized preparation; do not add a framework, approval loop or fixed polling cadence.
