# Runner operation contract

Read completely before choosing or operating a Runner route from [delegation](../SKILL.md).
Use [planning research](planning-research.md) to supply primary evidence and require a concrete repair choice during authoring.

## Actual execution and checks

Use `plan-authoring` followed by `plan-execution` by default. Code must be authored by an actual
Agent Runner code-producing execution step and pass the [owner-selected mode's](owner-selected-mode.md) required verification;
an approved plan or self-review is not code-producing execution or independent review. Outside
Runner, supply requirements, measurements, findings and acceptance criteria, not a prewritten
implementation patch for Runner merely to apply. Subagents may coordinate, operate, read and
review Runner work, but may not implement it independently.

Before launching direct declarative `plan-execution`, qualify the exact submitted plan bytes with the installed stock parser and its serializer/round-trip; retain the accepted step/check scope bound to those bytes. Do not guess the grammar or prepend explanatory Markdown the parser has not accepted. A parsing failure holds launch; preserve the failed packet and prepare a fresh supported correction without changing frozen inputs.

Choose supported pipelines and worker steps by their current capabilities, not just their
names. `polishing` finalizes and stages an existing change set without committing; do not
assume it replaces implementation from scratch. Commit authorization is defined in
[AGENTS.md](../../../../AGENTS.md#working-agreements). A stage-only result can be followed by a
separate authorized coordinator commit. Verify the execution route's commit behaviour before
starting; do not invent a no-commit mode. If the task forbids commits and no supported
noncommitting route fits, report that conflict and continue independent authorized work
rather than implement by hand.

**Who runs which check is settled in
[agent-runner.md](../../finalization/agent-runner.md).** It carries the division between what
a step proves inside its sandbox and what the owner runs on the host, with reasons and dates.
Read it before scoping gates; do not duplicate or re-derive that division per task.

That file is reached by reference, not by configuration. The runner's `finalization` setting
accepts only `auto`, `none`, or a path ending in `/SKILL.md`, so it stays at `auto` and the step
loads `.agents/skills/finalization/SKILL.md`. **A task's gates section is what carries the
division to the step**, and it is authoritative for that step — so every runner task names the
required checks explicitly, says which ones the owner runs afterwards, and points at
`agent-runner.md` for the reasoning.

## Track every Runner error and failed run

Track every actual Runner error or failed run in an issue record, including expected quota,
configuration-validation and operator errors; classify them truthfully without asserting a
confirmed Runner bug. Reuse or update a matching existing issue with each new run occurrence;
create a new issue only when no matching record exists. Record concise English observed error,
actual run and mode, expected/actual behavior, Source/configuration context, sanitized public
evidence and explicit Unknowns; retain the issue ID and report receipt. Include no private
prompts, transcripts, credentials or sensitive payloads.

Use supported `unexpected_issue_report` only when the coordinator deliberately concludes that
behavior is unexpected, as its contract requires. If the error cannot be represented truthfully
through supported reporting, or reporting is unavailable, retain an explicit local issue marked
pending publication and tell the owner; never claim it was published. Tracking does not itself
stop authorized product work: continue through supported recovery, preserving code, frozen-input
guards, roles and checks, without forcing readiness or blindly retrying.

## Frozen configuration and backend recovery

- **Trusted-check configuration is frozen at run start.** Editing
  `LOCAL_ARTIFACTS/agent-runner.json` while a run exists leaves that run unable to resume *and*
  unable to cancel — the protected-input guard refuses both. Prepare the selection before
  starting, never during.
- **A backend upgrade mid-run strands the run, and every run started after it from the same
  MCP session.** The runner records an immutable provider-policy receipt per role at the first
  probe and refuses a later probe that disagrees (`ERR_PROVIDER_POLICY_CHANGED`). Codex
  auto-updates on an hourly schedule; on 2026-10-10 it swapped 0.162.0 for 0.162.1 in the
  second the run was created, which killed the reviewer at launch and then failed every
  dispatch, because the long-lived MCP server kept resolving the old binary while the shell
  resolved the new one. The symptom is a detached continuation that exits before durable
  acknowledgement, with no rollout session written. Neither run could be recovered; both were
  cancelled. The way through is to drive the pipeline from the CLI — `agent-run run <pipeline>
  --project … --task …` — where both probes see one binary, which also puts the real error on
  stderr instead of leaving it to be dug out of `state.json`.

Before freezing a commit-capable run, qualify the actual repository commit-clarification path
and its Git-ignore status; external configuration does not relocate it. Prefer omitting
`artifactRoot` for the supported ignored `LOCAL_ARTIFACTS` default unless the actual
alternative canonical commit path is qualified. Guidance/configuration loading alone is
not commit-workspace preflight PASS. Preserve/reconcile rejected frozen runs before fresh
configuration; do not change Source or ignore rules, or edit frozen inputs, to recover.

Aliases live in the runner-root catalog or in the project's own
`LOCAL_ARTIFACTS/agent-runner.json`; a project selection replaces the root selection, so list
every alias the pipeline needs. Trusted commands execute in the project directory and inherit
the runner's environment. `local.properties` in each Android module removes the `ANDROID_HOME`
dependency for Gradle.

Before an audit launch, verify its actual workspace kind and qualify primary-source membership and
protected/control-root snapshot footprints separately. Git selection can still leave reserved roots
such as `.claude` recursively capturing ignored/generated trees; external infrastructure alone does
not remove source-side controls. Use supported scope/placement controls and keep custody/receipt
writers outside the active snapshot target. Preserve unrelated dirty copies; a smaller Git selection
is not move/deletion authorization. A plain source export is warranted only when the actual footprint
includes unsuitable ignored/generated content and no supported bounded selection is available. Then
verify all tracked blobs/modes and use supported external infrastructure, without clone/worktree/ref
writes or ad hoc snapshot exclusions.

On `workspace_changed`, distinguish the actual failing snapshot from a later comparison. Identify
native bookkeeping through its actual producer and path/type/mode; explicitly admit already-existing
state only before a fresh freeze, never by repairing a frozen baseline or relaxing its guard.
A later sample cannot reconstruct an unretained failed capture.

Compare configured profile aliases and effective canonical directories in their own semantic
domains; alias-to-directory resolution is not a mismatch and does not authorize private-store access.

After `invalid_discovery`, inspect supported diagnostics and the owning schema/semantic contract;
unretained fields/body leave the exact cause Unknown. Retry only with a concrete supported correction:
targeted same-run feedback when available, or fresh reviewed requirements when an evidenced contract
gap supplies a new corrective change. Otherwise preserve the blocker without blind retry, new run or
manual report repair. Keep the same authorized scope, roles and guards.

Follow the [2026-11-06 owner direction](owner-selected-mode.md): explicitly select `combined` for every fresh pipeline, including `plan-authoring`, `plan-execution`, `polishing` and `audit`, with its qualified role choices and authorized quota fallback.
The managing operator verifies the owning run's actual public mode through the supported API before acceptance or an authorized coordinator commit; defaults are insufficient.
Managed code roles report their assigned mode/protocol and complete that mode's actual verification, without managing their own Runner or adding a CLI self-status/admission/retirement probe.
Operator mode observation and HOST work are not additional Native checks or completion/commit prerequisites. Combined requires primary convergence followed by the full independent review gate; report its actual evidence.
The operator uses a supported stop on mismatch; preserve required checks and the coordinator's full independent ZERO.

Before a fresh start, reconcile one self-contained role-facing task/context against the current scoped Native
catalogue and changed guarantees. Identify its complete Runner Native `requiredChecks` inventory separately
from mandatory post-DONE HOST obligations; historical inventories are provenance, not competing catalogues.
The discovery catalogue is the union of Native commands applicable somewhere in the complete canonical plan, not all repository recipes; per-step assignment follows separately. Every selected command enters discovery and needs that global relevance; remove unrelated selections only before the fresh run. Preflight known Native capability needs against the exact task-local configuration's selected trusted command/vector and capability identity; definitions alone, an empty selection or another config do not qualify the check. For example, a JVM `mktemp` check needs its admitted scratch-enabled definition selected. Read-only resolution/preview is not preparation or execution PASS; if a frozen run lacks it, use supported terminal reconciliation before a fresh admitted config/run, without frozen/global edits, broader grants or HOST substitution.
Inspect the FIRST role's published discovery `requiredChecks` immediately (`plan-execution`: `bootstrapProgress.worker.work.discovery.requiredChecks`, before `workerValidation`). Use a supported stop/reconciliation for an admitted-check/global-relevance mismatch; never treat extra HOST checks as informational or wait for merge/writable work.
For `plan-execution`, independently verify merged `validationSchedule.commands` against the admitted complete-plan Native union and resolve every step's command-index mapping against that step's admitted commands before accepting the schedule. Compare `pipelineState.requiredChecks` with the current step's resolved subset before accepting it, not with the complete-plan union. Compare exact command identities, not local C-IDs, which may be renumbered between discovery and steps. Preserve every admitted check: missing/extra commands or incorrect step mappings require supported stop/reconciliation. Apply this domain distinction to other routes only when they expose those domains; do not assume these `plan-execution` fields exist in authoring or another route.
Put read-only discovery versus workspace-write FINALIZE and real extra-authority needs in that task/context;
local operator guidance is not injected. Report genuine Native needs truthfully, never force empty reports.
Before attributing an admission failure or changing authority, qualify the actual
`capabilityRequirements`/`environmentBlockers` against their owning schema and the command's
assigned executor and phase. Inability during nonexecuting read-only DISCOVERY alone belongs
in `summary` as phase rationale, not as an unmet requirement of an assigned Worker's writable
FINALIZE; this applicability distinction is not a schema ban or proof that genuine execution
needs are absent. Every accepted environment-only row participates in admission even with
empty `capabilityRequirements` or evidence denying an eventual restriction; reconciliation
cannot erase it. Preserve genuinely evidenced nondelegated restrictions of the assigned
executor without forcing empty reports, grant workarounds, HOST substitution or frozen-report
repair, and hold if a genuine unmet need remains.
A check assigned solely to HOST stays mandatory outside Native inventory/capability/environment-blocker
reports; an unselected HOST command does not acquire Native applicability merely because it is mandatory.
Keep mandatory HOST acceptance after whole DONE, run-owned process retirement and fresh separate
quiescent ownership; if the route used a foreground owning CLI, also require its actual exit.
HOST is not a Native check or Native-commit prerequisite. Preserve every scope-appropriate gate.

For a custom STDIO client, intermediate `run_wait` activity requires `progress:true` and
`tools/call` `params._meta.progressToken`, beside `params.name` and `params.arguments`, not
inside the tool arguments. Dispatch `notifications/progress` while awaiting the same call's
response, matching `params.progressToken`; `params.progress` is the public activity revision
and `params.message` its message, not a heartbeat, finding count, percentage or full status.
Intermediate progress does not resolve `run_wait`: keep that one wait until terminal state,
required input, proved owner loss or timeout; do not replace it with status polling or start
a second wait.

### Single-wait observation helper

Use [observe-run-wait.mjs](../scripts/observe-run-wait.mjs) for one owned STDIO observation.
First qualify the Node executable, Runner entry, canonical project/run binding and sole
observation interval independently. The two assertion flags record that caller responsibility;
neither cwd nor this helper discovers ownership. Keep other controllers and the live audit untouched.
Supply absolute paths and a fresh output directory whose parent already exists:

```bash
"$qualified_node" .agents/skills/delegation/scripts/observe-run-wait.mjs \
  --node "$qualified_node" --runner-entry "$qualified_runner_entry" \
  --project "$canonical_project" --run-id "$qualified_run_id" \
  --cursor 0 --wait-ms 900000 --output "$fresh_receipt_directory" \
  --qualified-binding --sole-observer
```

The helper initializes protocol `2025-11-25` and sends exactly one `run_wait`, with no
discovery, polling, retry or run control. There is no shorter client request deadline.
Matched progress is appended to `progress.jsonl` before immediate JSONL dispatch to stdout;
unmatched tokens are ignored. `outcome.json` retains the actual final JSON-RPC response,
including `structuredContent`, and takes `activityCursor` only from that response. Missing
final responses/cursors remain `Unknown`. `returned` means the wait returned, not that the
run passed; `timedOut` is a normal server result. JSON-RPC/tool errors and protocol,
transport, EOF, process, interruption and receipt failures remain distinct.

The directory is created exclusively with mode `0700`; the three receipt files use exclusive
creation and mode `0600`. `stderr.log` retains at most the first 64 KiB of the owned server's
stderr, with observed/retained byte counts and truncation metadata in the outcome. Collect only
public protocol/diagnostics, never provider stores, transcripts, prompts, credentials or environment dumps.
Receipt failures preserve partial files and report failure; an absent or incomplete outcome is
not evidence of success. The helper ends its own stdin normally after a response or client
failure, observes process exit and stream closure for at most five seconds, then releases local
handles without signaling the server or durable run. Cleanup reports actual exit or `Unknown`
and whether the limit was reached. Exit code zero requires a normal wait result, no client
failures and observed successful cleanup; it proves neither run retirement nor product acceptance.
The single [controlled protocol test](../scripts/observe-run-wait.test.mjs) uses local streams,
never a live run: `node --test .agents/skills/delegation/scripts/observe-run-wait.test.mjs`.

### Controller ownership and retirement

Bind managed controllers by `/proc` executable identity, the pinned Runner entry and exact
project/run arguments appropriate to their supported route; Node can expose `comm=MainThread`.

Installed launchers can execute from immutable runtime payloads outside the outer installation;
qualify the actual entry using its public payload manifest and launcher modules, rather than
an installation-path prefix. A different directory alone proves neither foreign ownership nor
a version mismatch, and a negative outer-prefix-only census does not establish retirement.

Revalidate PID + startTicks before comparisons; name/CWD alone or an empty `node`/`nodejs`
comm-filter result proves neither ownership nor retirement. Keep the census scoped,
including separately tracked owned descendants. An unreadable known or evidenced in-scope
identity leaves retirement unresolved; unrelated unreadable processes do not create a global
blocker. Public DONE or CPU/I/O activity alone proves neither owned-process exit nor semantic
progress/command success. Record match results/hashes instead of raw argv, environment,
prompts or authentication.

## Observed environment limits

- A historical `spawnSync python3` denial (`EPERM`) blocked `assertLabelsFit` in
  `tools/render-watch-ring-designs.mjs` inside that Runner executor; a separate trusted
  `just check-designs` environment ran Python/Pillow successfully. Current `assertLabelsFit`
  uses asynchronous `runFile` (`execFile`), not `spawnSync`: evaluate it in the actual executor.
  Neither fact proves current Native generation availability/PASS; preserve the task's Native/HOST division and authorship.
- **Sockets are denied**, so Gradle never starts: `just check-wear`, `just check-watchface`.
- **No network**, so a recipe that fetches needs a pinned artifact or it is the owner's.

A gate that cannot start is reported through the environment-blocker path. Necessary host
checks and captures may run outside Runner; that permission does not transfer code authorship.
