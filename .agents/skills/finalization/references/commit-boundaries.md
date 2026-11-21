# Focused commit boundaries

Apply before scoping a Runner task/plan and again before integration or staging. This is
the owning rule for dividing work; [commit-message.md](commit-message.md) owns wording.

## Plan one cohesive problem

By default, work sequentially on one backlog item or cohesive problem in the main working
copy. Prepare actual Runner plans as focused commits with clear scope, necessary checks and
independent review. A deliberate cohesive multi-commit plan is allowed; each step must remain
reviewable and coherent rather than mixing unrelated backlog features.

Do not create clones or worktrees solely to fill an active Runner wait or implement a small
unrelated skill/prose change. Queue those changes until the owning current integration
boundary is accepted; read-only preparation, investigation and review may continue. The
owner's explicit 2026-10-26 direction is sequential implementation in the main working copy.

Include the owning code's necessary tests, documentation, contracts and generated exports
in its coherent change. Do not separate a generator from required output or mix an
unrelated feature merely to hit a line-count target. Size alone does not define cohesion.
Code, generator source changes and canonical runtime exports require actual Runner
execution. Delegated design subagents may regenerate review/mock art with unchanged tools;
design/documentation retain delegated authorship and independent review under
[delegation](../../delegation/SKILL.md).

## Finish the current integration boundary

Complete the current item's applicable checks, the coordinator's full independent ZERO
after the last correction, and the authorized focused local commit before adding the
next unrelated implementation to the coordinating working copy. Earlier Native commits
may already exist as described below; they do not by themselves close HOST acceptance.

Resolve an actual blocked check or report its concrete blocker and required next action.
Do not accumulate additional unrelated features in the same uncommitted pool while it is
blocked. Independent read-only preparation, investigation and review may continue.

For polishing, use one item's existing cohesive candidate at the integration boundary.
Several unrelated implemented backlog items are not one polishing scope merely because
they are already present. An existing mixed diff needs reviewable problem/commit boundaries
before further unrelated work; do not rewrite frozen run/task/config/state to obtain them.

## Independent implementation streams

Use separate implementation streams or isolation only where actually needed and within the
owner's authorized scope. Each stream still requires its own actual Runner execution/review
and an explicit focused commit/integration boundary. Do not pour results into one uncommitted
integration pool. Preserve dependencies, ownership and existing changes when bringing a
completed stream back to the main working copy. Isolation does not authorize bypassing
another run's protected ownership. Linked worktrees share branch/tag/stash refs; serialize any external commit, stash, tag or other ref write against every guarded Runner lifecycle, including read-only turns, not only Source ownership. The owning pipeline's admitted Native commits keep their existing contract; independently authorized HOST/device/read-only work that writes no refs may continue.

## Preserve the Native/HOST and commit contract

Actual plan-execution may create its focused commits after the pipeline's required Native
checks and independent reviews. Candidate HOST acceptance follows the entire owning run's
DONE, process retirement and quiescent ownership. Those checks are not a new prerequisite
for a Native step's own commit. See [agent-runner.md](../agent-runner.md#4-checks-who-runs-what)
for that division; focused integration does not change it.

A coordinator commit requires all applicable checks and the full independent zero-findings
pass after the last correction. Polishing remains stage-only; an authorized coordinator
commit is a separate action, not a conversion of an incomplete/canceled run into success.
Stage only the reviewed cohesive change under [finalization §7](../SKILL.md#7-staging-and-commit-boundary).

Use standing owner authorization where it applies; this rule creates no new permission
flow. A task-specific no-commit instruction overrides that authorization. Keep that result
at its reviewed boundary, report the restriction and continue permitted independent work;
do not evade it by accumulating unrelated implementation in the same working copy.
