---
name: test-authoring
description: Design, change, and review WardPulse tests for necessary coverage, deterministic behavior, and fast execution. Use when adding tests, changing fixtures, removing redundant cases, or reviewing test cost during finalization.
---

# Test Authoring — WardPulse

Follow [delegation](../delegation/SKILL.md): code and test edits are authored only by Agent
Runner code-producing execution steps with independent review. Delegated documentation prose
is permitted; it does not authorize implementation outside Runner.

Use existing Rust in-module tests from `core/`, flat Flutter `test/` suites, Wear JVM/device
tests and native/tool harnesses. Find owners and commands in `AGENTS.md`, component READMEs
and `justfile`; do not add a framework or dependency for this workflow.

- Every test MUST catch a concrete regression or protect a distinct observable contract.
  If its necessity cannot be explained, remove it. Do not add tests for reassurance,
  coverage counts, copied wording, or implementation shape.
- Inputs, fixtures and assertions MUST be self-contained. Use minimal, neutral synthetic
  values. Never use names, paths, identifiers or contextual details from unrelated projects,
  including as deny-list entries or regression fixtures. Keep fixtures sanitized.
- Add regressions for reproduced defects and known fragile boundaries; retain RED→GREEN
  evidence proving the failure and fix. Elsewhere, test only an important uncovered contract.
  A change alone does not justify another test.
- Choose the smallest sufficient test with pure functions or injected effects. Use real
  processes, durable storage or devices only when their interaction is the contract being
  proved. Do not duplicate that proof across layers or multiply equivalent scenarios.
- Tests MUST be deterministic. Synchronize with events, awaited operations or controlled
  clocks. Artificial sleeps, timing-based ordering, retry-until-green and unnecessary polling
  are prohibited. Await teardown of every owned resource.
- Preserve distinct safety, recovery and failure-path guarantees. Before deleting a redundant
  test, name its retained replacement. Never weaken assertions, skip or disable failures,
  or lower concurrency to hide a race.
- Affected ordinary host test execution with warm dependencies has a 60-second development
  budget. Measure it and remove avoidable cost; report build, toolchain and emulator setup
  separately. This is not a budget for `just test-all` or a reason to omit required gates.
  Do not enforce it with a flaky wall-clock assertion in a unit test.
- Keep an expensive test only when its necessary guarantee cannot be proved cheaply. Classify
  it as slow, integration or device where appropriate; document its guarantee, owner and
  explicit invocation in existing owning component or command documentation. Finalization
  does not repeat expensive runs without a concrete unresolved risk; required gates remain
  mandatory. An unrun check is not a pass. Live-provider tests remain opt-in.
- Run affected coverage and every required gate; repeat broad runs only for a concrete
  unresolved risk. Report actual outcomes and elapsed times. Existing gate requirements and
  the host/Runner check division remain mandatory.
