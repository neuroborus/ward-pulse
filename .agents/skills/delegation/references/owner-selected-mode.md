# Owner-selected Runner mode

The owner's 2026-11-06 direction supersedes the 2026-10-31 Lazy instruction:
use Combined for fresh planning and code runs, use Opus as Worker while its quota
is available, and switch all roles to Sol when that quota is exhausted.

Explicitly request supported `combined` mode for EVERY fresh pipeline, including
`plan-authoring`, `plan-execution`, `polishing` and `audit`, and their replacements. The managing operator
verifies the actual publicly resolved mode and role selections before acceptance;
a requested value or descriptor default is insufficient. Use a supported stop and
reconcile a mismatch rather than silently selecting another mode.

For a Worker role, request backend `claude`, native model selector `opus` and
profile `current` while available. The public native CLI advertises `opus`; treat
it as an opaque native selector, not a guessed versioned model ID or proof of
remaining quota. Use Sol for Planner, Reviewer and Arbiter, retaining qualified
profile/effort selections. Plan-authoring has a Planner, not a Worker; its Planner
therefore remains Sol. Qualify actual role selections before freezing a new run,
without inspecting private profile stores or probing accounts merely for quota.

On actual Opus quota exhaustion, reconcile the owning lifecycle through supported
controls, preserve work and receipts, and start a fresh all-Sol Combined route
within the approved scope. The owner authorizes this fallback; it does not permit
mutating frozen role configuration or claiming an automatic in-run hot swap.
The final audit also uses Combined. Keep its Fable-discovery/Sol-reviewer role
preference while that backend is available. After actual Opus quota exhaustion,
the newer all-Sol fallback also applies to that audit; the older Fable preference
must not prevent it. No quota state is assumed here.

Combined adds primary convergence and read-only clean confirmation before the
full independent review gate in coding pipelines. Require and report its actual
verification; old Lazy self-review/Worker confirmation is not that independent
gate. Managed roles follow their assigned protocol without managing their own
Runner or adding CLI self-status/admission/retirement probes.

This direction applies to fresh runs only. It does not alter actual Runner-only
code authorship, delegated design/documentation independent review, required
checks, Native/HOST assignments, retirement or commit boundaries. The coordinator
still completes a full independent zero-findings pass after the last correction.
Standing commit authorization requires the selected mode's actual verification;
polishing remains stage-only and push/amend permissions do not change.

Leave historical/frozen runs, plans, reports, configurations and role selections
unchanged. Carry the new mode and role choices in fresh supported launch inputs;
this prose does not mutate an existing run or authorize hand-editing its inputs.
