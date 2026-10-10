# Finalization for Agent Runner — WardPulse

This is the check division an Agent Runner step works under. It is not a skill and takes no
frontmatter, so nothing selects it automatically; it is reached only by reference. A runner
task's gates section names it, and `.agents/skills/delegation/SKILL.md` points the coordinator
here before scoping those gates.

It cannot be the runner's `finalization` setting. That setting takes `auto`, `none`, or a path
ending in `/SKILL.md` and nothing else, so `LOCAL_ARTIFACTS/agent-runner.json` leaves it at
`auto` and the step loads `SKILL.md` beside this file. This file supplies what that one leaves
to the operator's judgement, by way of the task.

> `SKILL.md` beside this file stays the contract for work done by hand on the host, and must
> not be edited to suit the runner. Where this file is silent, that one applies.
>
> Last updated: 2026-10-10.

## 1. Scope Review

- [ ] Changes match the plan step and the current phase in `docs/DEVELOPMENT_PLAN.md`.
- [ ] Root files stay short and operational; durable requirements stay under `docs/`.
- [ ] No generated platform project noise was added unless the task asked for it.
- [ ] No unrelated local or owner changes were reverted.
- [ ] Changed OpenPencil sources and their generated runtime exports travel together.
- [ ] Changes follow root `AGENTS.md` working agreements.

## 2. Boundary Review

- [ ] Rust domain logic stays under `core/`.
- [ ] Provider normalization stays in Rust; platform transport and credential storage stay in
      app shells.
- [ ] Flutter phone work stays in `apps/phone_flutter/`.
- [ ] Wear OS Kotlin/Compose work stays in `apps/wear_android/`.
- [ ] Watch Face Format resources stay in `apps/watchface_wff/` and are generated, never edited.
- [ ] Generated bindings stay in `bindings/*/generated/`; interface design stays in
      `core/ward-pulse-ffi/`.
- [ ] Shared contracts stay in `schemas/`; sanitized examples stay in `fixtures/`.

## 3. Security Review

- [ ] No provider credentials, authorization headers, raw prompts, or sensitive raw provider
      payloads entered the change set.
- [ ] Logs, fixtures, examples, and docs use redacted or mock data.
- [ ] Credential rules in `docs/product/SECURITY_MODEL.md` still match implementation
      assumptions.
- [ ] Wear OS and watch face surfaces gained no credential entry or credential storage.

## 4. Checks: who runs what

The task's own gates section is authoritative for a given step. In its absence, this division
applies, and it is the reason this file exists.

**The step runs these in its own sandbox** — they work in the ordinary worktree:

- `just check-phone` — Flutter formatting, analysis and tests.
- `just check-designs`, `node tools/render-watchface.mjs --check` — generated art and face XML.
- `just validate-fixtures` — schemas and golden fixtures.
- `git diff --check HEAD`.
- Rust gates from `AGENTS.md` when `core/` changed.

`just validate-watchface` belongs here too, but only with its artifact granted. The recipe
fetches the Watch Face Format validator JAR, so the step declares a pinned artifact — the asset
URL and its `sha256` — and the runner supplies it from cache. The worker reported
`unsupported: []` for this command on 2026-10-10, meaning nothing about it is ungrantable; an
earlier run failed it as `insufficient-authority` only because the alias in
`LOCAL_ARTIFACTS/agent-runner.json` granted `scratch` and `cache` without the artifact.

The toolchain is warm inside the project: the Flutter SDK lives in `.toolchains/flutter` and is
writable, as are the Gradle, pub and XDG caches. There is no network — nothing may be
downloaded.

**The owner runs these on the host, after the step:**

- `just check-wear`, `just check-watchface`. Both start Gradle, and Gradle opens a loopback
  socket for its file-lock listener; the agent sandbox denies sockets, so Gradle does not start
  there at all. That is an inability to run, not a failing test.
- Every device check: `adb`, emulators, inspecting a screen or the watch face.

**`just check-docs` is disputed, and the dispute is recorded rather than settled.** This file
placed it in the sandbox column on 2026-10-02. On 2026-10-10 a worker declared it
`unsupported: ["network"]` and the run stopped on the environment blocker. Neither side has been
proven: inspection that day found the build to be local — `npm run docs:build` runs a Vite build
against an installed `node_modules`, and the site sources carry no remote fonts or CDN
references — but nothing demonstrated the build completing with the network actually denied, and
the worker's report is a declaration of what it believes it needs rather than an observed
failure. Until someone runs it offline and reports the outcome, treat it as the step's to
attempt and the owner's to confirm, and do not quietly move it to either column.

**The owner's work is never a precondition of the step's commit.** A step that waits for it
cannot produce complete terminal evidence, and the run fails — this happened on 2026-10-01
(finding `R101`, `ERR_INVALID_PLAN_EXECUTION_OUTPUT`). Prove readiness with a regression, not a
screenshot, and let the owner verify afterwards.

A gate that cannot start for an environment reason is reported through the runner's
environment-blocker path. Never weaken a test, an assertion, a gate, a skill or validation
infrastructure to make a check pass, and never report a check that did not run.

## 5. Documentation Review

- [ ] `docs/README.md` links any new durable document.
- [ ] The Vocs page and `docs/site/vocs.config.ts` navigation are updated for documentation
      exposed on the site.
- [ ] Vocs pages import authoritative Markdown instead of duplicating it.
- [ ] `README.md` still describes the current repository shape and commands.
- [ ] Product, provider, release or security docs are updated when behaviour or boundaries
      changed.
- [ ] A locked baseline in `docs/product/` changed only through a dated revision that records
      the measurement, the device and the decision.

## 6. Commit

A plan-execution step commits its own work when the pipeline authorizes it; a polishing step
stages and stops. Either way:

- The message is a single Conventional Commits subject line: `type(scope): imperative summary`,
  about 72 characters or fewer, matching the scopes already in `git log`.
- **No body unless the change is genuinely unclear without it**, and no file lists.
- **No trailers of any kind.** No `Co-Authored-By`, no generator attribution, nothing. This
  repository has none, and it stays that way.
- Stage only the files belonging to this change set. Never `git commit --amend`, never rewrite
  history, never touch the owner's unrelated changes.

## 7. Local artifacts

This file is versioned with the repository and changes only through a reviewed edit, the same
as the skill beside it.

`LOCAL_ARTIFACTS/` is gitignored and never committed. It holds the runner's own configuration,
task and plan documents, the fixes list and run state. A step may read it; it changes nothing
there except the artifacts the runner itself owns.
