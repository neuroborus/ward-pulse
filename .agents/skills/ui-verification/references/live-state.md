# Live state and custody

Use BEFORE every persisted ordinary Mock transition, a shared-state equality guard around
read/test-only observation or an interval without writer custody, and when classifying a
post-test state delta. Taking a snapshot does not freeze a normal live store or establish
ownership of later writes.

For ordinary Mock changes, including private regression acceptance, follow the phone owner's
[custody and restoration contract](../../../../apps/phone_flutter/README.md#reproducible-debug-mock-data)
for entry and restoration. Public-image intent does not limit that contract; unproved required
custody holds entry. Later saved-mode or visible Live/widget restoration does not prove the
pre-entry barrier or unobserved recovery/wake/notification bookkeeping preservation.

## Record before deciding

Before shared-state hash equality/drift classification, bind BOTH expected and actual to
the exact required object/path or named field AND byte representation (container XML versus decoded value).
Compare matching domains; missing bindings stay Unknown. Hashes of different representations alone do not prove drift, a writer or corruption.
Keep applicable byte guards exact: decoded-value equality cannot replace a required container-byte guard; never canonicalize or add tolerance to obtain equality.
Retain bounded expected AND actual presence/hashes, state source and relevant target identity, operation/phase, snapshot/read times and available
generation/write times with their origins/timezones. Record whether writer custody covered
the interval, authorized writes if any, and known attribution or Unknown. Capture these facts and the exact phase-applicable predicate BEFORE evaluating its guard;
retain actual rows/readbacks in failure evidence.

Before issuing an asynchronous retirement request, qualify the owning bounded observation, terminal predicate and observation deadline. Request acknowledgement alone is not retirement: expected in-flight samples are Waiting, not terminal failure. Apply the final retirement guard only after conclusive owner-qualified evidence or at that deadline; do not extend it merely to obtain absence.

Missing failure-point rows or predicate remain Unknown.
If collection fails, retain the facts obtained and that failure; missing actual data is Unknown.
Keep secrets/raw normal payloads out of diagnostics; extract ONLY the exact intended fields from their owning record BEFORE any output, following [diagnostic output privacy](../../../../docs/ANDROID_TOOLCHAIN.md#diagnostic-output-privacy).
A substring match inside a payload/container is not projection; never emit aggregate complication-data or timeline bodies. Missing/ambiguous fields stay Unknown; do not widen output.
Do not move or mutate state to collect them.

Before a pending-state guard classifies a store’s files, bind its footprint to the exact owner/path
and platform sidecar contract; retain bounded actual names and their classification before deciding.
A shared stem is not shared ownership: a Source-proven `watch_summary_test_123.xml` store is not
a sidecar of `watch_summary.xml`. Exclude only positively established independent stores from
that object's pending predicate; genuine backup/pending evidence and unexplained potentially
related files remain HOLD. Do not delete files or discard ambiguous matches to obtain a clean
guard. Absence of sidecars or stable hashes alone proves neither drained work nor quiet writers.

A later observation is its own timed sample. Never reconstruct unretained failure-point facts
or which guard failed from that sample. Content/timing that differs from private fixtures can qualify
the evidence, but cannot identify a writer. Test-only intent or JUnit success alone proves
neither private backing identity nor absence of a normal-store write.

## Apply the actual phase and ownership

For an unowned live-writer interval, byte drift alone proves neither test write nor failed
restoration. Preserve current/newer data and record the delta with attribution Unknown when
unproved. An independently admitted read/test-only observation need not require the old
normal snapshot to remain equal or impose quiet writers solely because it drifted. Use fresh
phase-appropriate evidence; retain required same-operation caller/artifact/instance/selection
brackets and leave any claim without its actual input join Pending. This grants no new action.

Controlled publication, direct-data mutation and owned recovery retain their strict manual,
current-target/ID, quiet-writer, arm-before-write, custody and recovery guards. An unexplained
change violating that owned contract, or genuine evidence that a test wrote normal state outside its allowed
owner, remains a HOLD for dependent acceptance/state-affecting work under the owning procedure.
Do not normalize the guard or overwrite a legitimate newer publication to obtain equality.

Do not restore an old snapshot, stop a producer, shut down, retry or probe merely to recover
equality or fill missing failure evidence. Recovery authorized by the owning procedure preserves newer
writes and verifies derived surfaces under [state/artifact checks](state-and-artifacts.md).
Drift diagnostics establish no test restoration, writer attribution, native paint or product PASS.
