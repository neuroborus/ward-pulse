# Owner-selected Runner mode

The owner's 2026-11-22 direction selects Independent for fresh Runner runs. Explicitly
request `independent` for `plan-authoring`, `plan-execution`, `polishing` and `audit`,
including fresh replacements of those pipelines.

| Role | Model | Native launch selection |
| --- | --- | --- |
| Worker while quota is available | Claude Opus 5.5 high | `claude`, `opus`, `current`, effort `high` |
| Reviewer and Arbiter | GPT-6.2-Sol xhigh | `codex`, `gpt-6.2-sol`, `current`, effort `xhigh` |
| Planner | GPT-6.2-Sol | `codex`, `gpt-6.2-sol`, `current`, qualified effort and context |

Plan-authoring uses the Planner choice. Use Fable for audit discovery and Sol for audit
review while Fable is available. Record any owner-selected audit model or effort override
in the fresh launch inputs for that run. Use the standing role selections for other runs.

Qualify the requested roles before freezing a fresh run. Verify the publicly resolved
mode, models, profiles and effort before accepting the launch. `opus` is the native
selector. Confirm its actual resolution to Claude Opus 5.5 using supported public
model evidence. A selector echo leaves the version unverified. Use a supported stop
and reconcile any mismatch or unverified required resolution. Use public evidence
without inspecting private profile stores or probing accounts merely for quota.

On confirmed Opus quota exhaustion, reconcile the owning lifecycle through supported
controls and preserve work and receipts. Apply the authorized all-Sol fallback by
starting a fresh Independent run in the approved scope. The same fallback applies to
audits. Keep the frozen role configuration for existing runs.

This direction applies to fresh runs only. It does not alter actual Runner-only
code authorship, delegated design/documentation independent review, required
checks, Native/HOST assignments, retirement or commit boundaries. The coordinator
still completes a full independent zero-findings pass after the last correction.
Standing commit authorization requires the selected mode's actual verification;
polishing remains stage-only and push/amend permissions do not change.

Leave historical/frozen runs, plans, reports, configurations and role selections
unchanged. Carry the new mode and role choices in fresh supported launch inputs;
this prose does not mutate an existing run or authorize hand-editing its inputs.
