# Finalization for Agent Runner — WardPulse

This is the check division an Agent Runner step works under. It is not a skill and takes no
frontmatter, so nothing selects it automatically; it is reached only by reference. A runner
task's gates section names it, and `.agents/skills/delegation/SKILL.md` points the coordinator
here before scoping those gates.

It cannot be the runner's `finalization` setting. That setting takes `auto`, `none`, or a path
ending in `/SKILL.md` and nothing else, so `LOCAL_ARTIFACTS/agent-runner.json` leaves it at
`auto` and the step loads `SKILL.md` beside this file. This file supplies what that one leaves
to the operator's judgement, by way of the task.

> `SKILL.md` beside this file stays the contract for host finalization within the delegation
> boundaries; it does not authorize code implementation outside Agent Runner and must not be
> edited to suit the runner. Where this file is silent, that one applies.
>
> Last updated: 2026-10-17.

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

Apply [test-authoring](../test-authoring/SKILL.md) during test authoring and finalization review
for necessity, determinism and measured cost. It does not replace required checks or change
the host/Runner division below.

The task's own gates section is authoritative for a given step. In its absence, this division
applies, and it is the reason this file exists.

**The step runs these in its own sandbox** — they work in the ordinary worktree:

- `just check-phone` — Flutter formatting, analysis and tests.
- `just check-designs`, `node tools/render-watchface.mjs --check` — generated art and face XML.
- `just validate-fixtures` — schemas and golden fixtures.
- `git diff --check HEAD`.
- Rust gates from `AGENTS.md` when `core/` changed.

The local Flutter SDK and warm dependencies can support ordinary checks without downloads.
Cache access depends on the executor: ordinary Codex workspace-write command attempts use a
fresh private `XDG_CACHE_HOME`, so prewarming the host cache does not populate it. Do not assume Gradle,
pub or XDG caches are shared or writable. Report actual command results; an artifact grant or
`unsupported: []` alone proves neither that a command ran nor that it can finish.

**The owner runs these on the host, after the step:**

- `just validate-watchface`. It needs the checksum-pinned JAR, Java execution and writable
  temporary storage, plus network access on a cold cache. On 2026-10-15, supplying the valid
  JAR did not let an ordinary Native attempt complete Java/temp-directory setup. An artifact
  grant alone is insufficient; assign it to a different executor only after observing that
  executor complete the actual command. The owner still confirms the required host gates.
- `just check-wear`, `just check-watchface`. Both start Gradle, and Gradle opens a loopback
  socket for its file-lock listener; the agent sandbox denies sockets, so Gradle does not start
  there at all. That is an inability to run, not a failing test.
- Every device check: `adb`, emulators, inspecting a screen or the watch face.

For build or validation artifact download, pin or cache changes, apply the conditional
empty-cache and reuse check in [host finalization](SKILL.md#4-tests-and-checks). Keep the
ordinary warm checks; they prove a different path. Do not add artifact grants, aliases or
repository projections merely to move an owner check into an ordinary step.

**`just check-docs` reaches no further than the checkout, as far as anyone has been able to
show.** This file placed it in the sandbox column on 2026-10-02. On 2026-10-10 a worker declared
it `unsupported: ["network"]` and the run stopped on the environment blocker — a declaration of
what it believed it needed, not an observed failure. Inspection that day found the build to be
local: `npm run docs:build` runs a Vite build against an installed `node_modules`, and the site
sources carry no remote fonts or CDN references.

Measured on the host on 2026-10-11, with `docs/site/dist` removed first so the build could not
be served by its own output. The recipe completed, exit 0, 47 files generated, with every proxy
variable pointed at a dead port and npm forced offline:

```
HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 ALL_PROXY=socks5://127.0.0.1:9 \
  npm_config_offline=true npm_config_registry=http://127.0.0.1:9 just check-docs
```

What that does not prove: a proxy variable is a convention a library may ignore, so this is not
socket-level denial. Neither `unshare -rn` nor `strace` was available on that host to produce
one — unprivileged user namespaces are refused and `strace` is not installed — so nobody has yet
watched the build with the network actually cut.

Treat it as the step's to attempt. A worker that cannot complete it should report the failure it
observed rather than declare the need in advance, because the one measurement anyone has points
the other way. It stays the owner's to confirm.

**The owner's work is never a precondition of the step's commit.** A step that waits for it
cannot produce complete terminal evidence, and the run fails — this happened on 2026-10-01
(finding `R101`, `ERR_INVALID_PLAN_EXECUTION_OUTPUT`). Prove readiness with affected existing
checks or necessary regression evidence under `test-authoring`; add tests only when justified,
and let the owner verify afterwards.

A gate that cannot start for an environment reason is reported through the runner's
environment-blocker path. Never weaken a test, an assertion, a gate, a skill or validation
infrastructure to make a check pass, and never report a check that did not run.

## 5. Documentation Review

- [ ] `docs/README.md` links any new durable document.
- [ ] The Vocs page and `docs/site/vocs.config.ts` navigation are updated for documentation
      exposed on the site.
- [ ] Vocs pages import authoritative Markdown instead of duplicating it.
- [ ] Root README begins with current product guidance, the approved PNG gallery and a user-guide entry.
- [ ] Apply [user-docs](../user-docs/SKILL.md) to public pages, routes and screenshots; refresh
      affected UI PNGs and their index, and keep developer/internal documentation out of the public site.
- [ ] Apply [docs-gate](../docs-gate/SKILL.md#keep-documentation-current) to reconcile affected
      documentation in this change set, or justify no documentation impact in the handoff.
- [ ] A locked baseline in `docs/product/` changed only through a dated revision that records
      the measurement, the device and the decision.

## 6. Commit

Follow the standing commit authorization in [AGENTS.md](../../../AGENTS.md#working-agreements).
Verify that the selected route respects the current instruction before execution. The
`polishing` pipeline stages an existing change set and stops; a later authorized coordinator
commit is a separate action under [finalization §7](SKILL.md#7-staging-and-commit-boundary).
For an authorized commit:

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
