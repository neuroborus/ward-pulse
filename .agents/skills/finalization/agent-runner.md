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
> Last updated: 2026-10-14.

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
- [ ] `README.md` still describes the current repository shape and commands.
- [ ] Apply [docs-gate](../docs-gate/SKILL.md#keep-documentation-current) to reconcile affected
      documentation in this change set, or justify no documentation impact in the handoff.
- [ ] A locked baseline in `docs/product/` changed only through a dated revision that records
      the measurement, the device and the decision.

## 6. Commit

Standing owner authorization dated 2026-10-13 permits Runner execution to commit within the
approved task scope by default after the pipeline's required reviews and checks. A task-specific
no-commit instruction overrides it. Polishing stages an existing change set and stops. Verify
that the selected route respects the current instruction before execution. This is local commit
permission, not push, amend/history rewrite, or unrelated-file authority. Either way:

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
