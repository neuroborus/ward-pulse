# Phone cache harness and original19 replay

The existing `run.sh`, `ConnectionCacheEngineTest.java` and
`ConnectionCacheEngineBridge.java` remain the Java harness and Flutter bridge. The
HOST-only `replay_original19.py` controller uses that bridge unchanged. Its entry point
is `main`; importing it launches nothing. `test_replay_original19.py` contains only
controlled filesystem, stream and process regressions.

## HOST invocation and acceptance boundary

From the canonical repository root, after the **whole corrective CODE run** reaches
DONE, its owning CLI actually exits when used, known/scoped processes retire, and Root
obtains a separate fresh public idle observation:

```sh
python3 -B tools/test-phone-cache/replay_original19.py \
  --final <second-corrective-commit> \
  --release-receipt <Root-admitted-whole-release-receipt> \
  --output <fresh-external-evidence-directory>
```

`--final` is a full commit object ID equal to released, clean HEAD. `--output` is an
absolute, absent directory outside canonical Source, with an existing physical parent.
It is created privately and exclusively through the qualified parent descriptor.
Journal and result writes also bind the evidence directory identity, so replacing a
path cannot redirect writes into Source. Do not reuse evidence directories. The script
must itself be the committed repository-local script at
`/home/neuroborus/Desktop/PROJECTS/PETS/ward-pulse`; another checkout, worktree, export
or copied controller is rejected.

Only HOST may run this invocation. Neither the controlled tests nor historical
FIXED-only measurements confer real replay, full-suite, Java, FFI or device acceptance.
HOST retains two distinct Flutter focuses from `apps/phone_flutter/` after that release
boundary:

```sh
flutter test test/openai_dashboard_repository_test.dart \
  test/codex_dashboard_repository_test.dart test/merging_connection_repository_test.dart
flutter test test/connection_snapshot_cache_test.dart \
  test/connection_credential_lifecycle_test.dart test/provider_sync_once_test.dart \
  test/apply_alert_settings_test.dart test/recovery_watchlist_test.dart \
  --plain-name 'connection absence ownership'
```

The first must preserve and pass all seven existing identity assertions. The second
retains the separate five-file absence-ownership obligation; a historical FIXED-only
result does not satisfy its rerun or the real three-leg replay.
HOST also owns fresh locked FFI build/load qualification and actual library identification,
unchanged complete `just check-phone` including JVM and formatting checks, documentation confirmation,
Android build/install, active APK/ABI/FFI identities and original native-frame review.
Root's full independent zero-findings review and admission of final Source and actual
HOST evidence remain necessary. F1 stays separate, known-open whole-app work before release.

## Root-admitted release envelope

`Release` consumes a new bounded JSON envelope that **links**, rather than edits or
replaces, Root's whole-run evidence. It is an admission input, not a way to discover
release or manufacture missing observations. Root must derive every projected field
from actual owning records and qualify these projections before invocation. The
`admittedBy` marker is an explicit trust boundary, not a signature or independent
proof of the historical events. Original records and observations remain intact.

The envelope uses `format: "original19-release-v1"`, `admittedBy: "Root"`, `runId`,
`final`, `source` (the exact canonical path), and `sourceIdentity`. An identity is
the ordered `[device, inode, uid, gid, linkCount]` list returned by `identity`.
All timestamps below are integer Unix nanoseconds.

`records` has exactly four named links, `done`, `cli`, `retirement` and `idle`.
Each link has an absolute `path` and `sealSha256`. Each linked JSON object has
`kind` matching its link, the same `runId`, and `observedNs`, plus:

| Record | Required observation fields |
| --- | --- |
| `done` | `status: "DONE"`, `head` equal to `final`; whole run, not one step |
| `cli` | `used` Boolean; when used, `actualExit: true`, `exitCode: 0`, and `identity`; when unused, `identity` and `exitCode` are null |
| `retirement` | `scope` equal to `runId`, nonempty `identities`, empty `remaining` and `unresolved` arrays |
| `idle` | `public: true`, `status: "idle"`, `lease: null`, `processes: []`; a separate later public observation |

Retirement identities are objects with exactly `pid`, `start` (Linux start ticks)
and `bootId`. They must be unique, belong to the current boot, and no longer be live
with that identity. A used CLI's identity must appear in that list. DONE, actual CLI
exit and scoped retirement precede idle; idle strictly follows retirement and precedes
this newly launched controller. Idle must be at most five minutes old at admission.
Unreadable in-scope identities supply no retirement proof.

`sealSha256` is SHA-256 of `encoded(file_seal(path))`, not just a content hash.
`file_seal` binds stable regular-file identity, filesystem mode, size and content hash;
`encoded` uses sorted compact JSON. Links must be distinct external regular files at
absolute physical paths; aliases through symlinked parents are rejected, including
for the envelope itself.
The envelope and linked records are themselves sealed until release. `metadata` is a
nonempty array of additional `{path, sealSha256}` file bindings for admitted runtime
metadata and source-binding receipts. No metadata content is copied into evidence.

The envelope also binds `indexSha256`, `logicalIndexSha256`, `refsSha256`,
`sourceSealSha256`, and `graphSha256`. Their producers are, respectively, the raw
canonical index, `Git.snapshot`'s NUL-delimited stage manifest and complete ref output,
`encoded(tracked_manifest(...))`, and `encoded(dependency_graph(...))`. These are actual
post-run measurements under Root's release authority. Seals include filesystem identities;
a previous run's hashes are insufficient. Do not run a replay to create its own admission.

`runtime` contains:

- `versions: {"flutter": "3.44.6", "dart": "3.12.2"}`;
- `executables`, mapping exactly `flutter`, `dart`, `tester`, `java`, `javac`, `python`
  and `git` to qualified absolute physical executable paths;
- `inputs`, a list of `{path, sealSha256}` records using
  SHA-256 of `encoded(runtime_seal(path, bookkeeping))`, where
  `bookkeeping = sdk_bookkeeping(sdk)` and `sdk` is the resolved pinned
  `.toolchains/flutter` directory;
- `ffiSha256`, the content hash of the qualified unchanged
  `core/target/debug/libward_pulse_ffi.so`.

Inputs must cover the pinned SDK, all named executables, the actual package-config
file, every external or SDK package root that config names, and the FFI artifact. Directory
seals include membership, regular-file contents/modes/identities and symlink identities
and targets without traversing them, with only the qualified engine bookkeeping below.
Root must include separately resolved toolchain
or package inputs reached through symlinks; `Runtime` rejects unsealed link targets.
It verifies SDK version metadata without invoking a writing SDK wrapper.
Root must use this same `sdk_bookkeeping` / `runtime_seal` recipe for every runtime input,
including an SDK ancestor or separately named leaf; the envelope's fields and format
remain unchanged. Ordinary metadata/record bindings still use `file_seal`.

`sdk_bookkeeping` checks the exact pinned `bin/flutter`, `bin/internal/shared.sh` and
`bin/internal/update_engine_version.sh` producer hashes in `SDK_PRODUCERS`. The normal
wrapper unconditionally runs the engine-version producer before its warm-cache checks.
The qualified outputs are exactly `bin/cache/engine.stamp`, whose bytes must equal the
immutable `bin/internal/engine.version` and the version JSON's `engineRevision`, and
`bin/cache/engine.realm`, whose bytes must be one newline. `Runtime.environment` excludes
engine-version and realm overrides. The two outputs may be absent at admission and
created by the wrapper; the stamp's temporary-file/atomic-rename replacement may change
its inode and creation mode. Their seals bind the derived bytes instead of leaf identity
or presence. Present outputs must be single-link regular files owned by the current
user, on the cache directory's device and group, with owner read/write permissions and
only nonexecutable bits permitted by mode `0664`. Symlinks and changed bytes hold.
Any `engine.stamp.tmp.*` entry at a verification checkpoint holds; temporary files must
be gone after readers retire. Cache directory identity/mode and all other membership
remain sealed. No SDK metadata is restored or adopted as a new immutable baseline.
The wrapper, SDK Git state, Dart/tool snapshot, executables, version metadata, packages,
Source and FFI retain their immutable seals. Cache lockfile creation, tool recompilation,
artifact downloads and other SDK mutations receive no exception. The controller still
launches the normal `bin/flutter` driver for every leg.

The new controller independently binds its own script, interpreter, PID/start and boot
identity. It also verifies its script against the released commit's immutable blob.

## Replay and custody

`Git` disables optional writes and replacement objects. `Custody` durably journals
`lock-acquisition-pending` before exclusively creating the canonical `.git/index.lock`,
before mutable state is sealed. An existing lock is confirmed foreign and left untouched.
An interrupted creation without retained descriptor/owner identity remains unknown,
even if the kernel created the lock. No pathname observation confers ownership.
Git launch, identity capture and stream setup share an owned-process
cleanup scope. Known Git sessions and descendants are retired and reaped even when
setup fails; uncertain launch ownership blocks restoration and custody release, just
as for Flutter legs. Under custody the controller captures all refs, raw index bytes and
logical index, complete tracked Source and parent-directory identities/modes, final test/support/import
inputs, pinned runtime/metadata inputs, the controller and unchanged FFI artifact.
Cleanliness rejects nonignored untracked inputs. Ignored SDK/package/FFI inputs are
separately sealed; generated test outputs are not a new Source baseline.

`dependency_graph` follows local Dart import/export/part edges from the named test and
the accepted eight owners, including the bindings. Local imports must be tracked;
external and SDK packages remain fixed through the runtime seals. Closure checking
includes the union of FINAL and substituted OLD import graphs. Final tests/support
may differ from their historical OLD versions; their bytes remain FINAL in every leg.
Production differences from immutable OLD
`ddc53fcbb139f221e9a46bd05566ab7e379de950` must be exactly the eight `OWNERS` paths:
connection lifecycle, merging/cache/dashboard repositories, dashboard load, provider
sync, recovery watchlist and the Java cache engine. Tests, support, imports, bridge
and every other final input remain identical through all three legs.

`StableFile` holds regular-file descriptors with qualified ownership, single-link
identity and modes. `Journal` exclusively creates a private, preallocated 1 MiB
fixed-slot journal; each slot is 16 KiB and contains one compact JSON record padded
with spaces and a newline. Unused slots are zero-filled. The last eight slots are
reserved for recovery. Each transition is synced. `restoration-armed` records immutable
FINAL blobs, hashes, identities and exact filesystem modes before
`substitution-may-have-begun` is durably recorded and before the first write attempt.
Descriptor writes preserve file identity. A failure before that boundary performs no
Source restoration writes. First-write and later partial failures still require exact
restoration once readers have positively retired.

`Processes` starts a fresh owned session per Flutter leg, with a 60-second deadline,
bounded streams, and bounded termination. Linux subreaper ownership retains orphaned
descendants; PID/start identities and descendants remain tracked across session changes.
Launch and stream setup share the cleanup scope. An interruption before the launched
root identity is captured leaves ownership unproven and holds Source transitions and
custody release; a later setup failure retires the tracked session and descendants.
Signals use Linux PID descriptors opened before the final identity comparison; a PID
reused between inspection and delivery cannot redirect a signal. Unavailable PID-descriptor
operations hold retirement. No unrelated process is signaled. Canonical Source readers block transitions.
The controller samples actual owned `/proc` command/executable identities, requires
per-leg `javac` of the engine and unchanged bridge, the subsequent Java bridge process,
fresh resulting engine/bridge classes, and a positive device/inode mapping witness for
the qualified FFI library in the owned pinned Flutter test process. A missed short-lived
compiler, inaccessible in-scope process, missing mapping or ambiguous witness **holds**;
presence of a binary nearby is insufficient.

Each leg runs the identical command from `apps/phone_flutter/`:

```sh
flutter test test/connection_snapshot_cache_test.dart \
  --plain-name 'connection absence ownership retains accepted A+B after late work' \
  --reporter json
```

`Reporter` accepts an oracle only at a line boundary, beginning with
`connection absence ownership oracle ` or exactly one `Shell: ` immediately followed
by that tag. Both framings share duplicate rejection and require the exact named test
to be known and active. JSON `print` messages containing the tag remain ambiguous and
are rejected; substring searches, repeated prefixes and arbitrary output are not accepted.
Account objects retain `id`, `connection`, `status`, nullable `spent` and allowance observations.
Completed absence reads, account order, healthy B, accepted A+B publication, late outcome,
actual publication and redraw/readback values are established before classifying flags
or assertions. FINAL must exit 0 with successful reporter completion and preserved A+B.
OLD must exit 1 at the named late-publication assertion, after accepted A+B actually
becomes late B-only publication and redraw. After verified exact restoration, restored
FINAL must exit 0 and preserve A+B. Earlier assertions, setup, compilation, FFI loading,
transport, timeout or missing evidence are infrastructure/validity failures, never RED.

The parser bounds UTF-8, 64 KiB lines, 4 MiB stdout, 4 MiB stderr, nesting and retained
evidence. It rejects duplicate keys, duplicate or unassociated oracles, malformed
JSON, wrong required types and nonfinite numbers. Standard `group` events from pinned
`test_core` 0.6.17 require `id`, `suiteID`, `parentID`, `name`, `testCount`, `metadata`,
`line`, `column` and `url`. IDs and counts are nonnegative integers excluding booleans;
the parent may be null, and the name may be any string (including empty) or null.
Metadata requires boolean `skip` and string-or-null `skipReason`. Locations must be
all null or positive integer line/column plus a string URL. Group values are validated
in memory and discarded; they confer no test-success or oracle credit. Unknown events,
including debug events, remain rejected. Repeated reporter event types and legitimately
nullable locations or oracle values remain valid. `seals.json`, the journal
and `result.json` retain no free-form widget labels; bounded printable Unicode labels
from the real producer are accepted and bound by the payload hash. These files
retain only allowlisted proof, hashes, identities and fixed failure
codes; raw output, error text/stacks, credentials, reports and private stamps are omitted.
Only controller exit 0 after complete `FINAL0 / OLD-named-semantic1 / restored-FINAL0`
and verified custody release is replay success.

## Failure handling

An error after an attempted substitution enters retirement and restoration handling.
Before release, complete Source/runtime/controller/metadata manifests and unchanged
HEAD, refs, raw index and logical index must match the sealed baseline. The index and
refs are never rewritten. An unknown/replaced lock is never released. Failed restoration,
unfinished readers or journal failure retains positively owned custody artifacts and
holds further work, even if Source bytes have been restored.

On exit 2, inspect the sanitized `result.json` and journal. A `result-persistence` failure
may leave no complete result file; the terminal summary retains the known custody
disposition. An unlink followed by a directory-sync failure remains a replay failure
without claiming the removed lock is still held. If custody is held or unknown,
stop ordinary work and return the evidence to Root. Do not delete/adopt a lock, kill a
process by name, change the baseline, rerun into the same output directory, or continue
with uncertain restoration. Root must reconcile exact owned PID/start and lock identities,
reader retirement and the sealed immutable restoration records before any recovery.
Uncatchable controller death or power loss likewise leaves the durable arm/custody records
for explicit recovery; it cannot report successful restoration or release.

Failure evidence uses `lockDisposition` to distinguish `not-attempted`, `foreign`,
`owned`, `unknown` and `released`. `custodyHeld` is true only for positively retained,
rechecked ownership, `"unknown"` for unresolved acquisition/replacement, and false for
the other dispositions. `lockIdentity` is null when no owner identity was retained.
The pending journal record and best-effort `custody-disposition` recovery record preserve
uncertainty even before a descriptor attribute survives. Unknown acquisition performs
no Source writes or lock adoption/deletion and waits for Root reconciliation.

## Native controlled regressions and check ownership

The earlier two-commit corrective inventory contained four commands, including
`just release-status`. That inventory and selection are historical. The Root-admitted
reporter correction has exactly these three commands, all from the canonical repository
root in its single step, **only in FINALIZE**:

| Command | Executor / purpose |
| --- | --- |
| `git diff --check HEAD` | Ordinary Worker; scoped whitespace |
| `python3 -B -m unittest discover -s tools/test-phone-cache -p 'test_*.py'` | Selected Runner-trusted vector; scratch only; controlled regressions |
| `just check-docs` | Ordinary Worker; actual citation/build gate for changed prose |

FIRST Worker/Reviewer DISCOVERY inventories applicability, actual capabilities and observed
blockers without executing these checks. Root independently qualifies the merged schedule,
step assignments and each current subset by exact command identity. Implementation,
focused development regressions and semantic review confer no FINALIZE credit.
The selected trusted vector runs through Runner after Worker returns, never inside an
agent turn. The historical release-status selection is absent from this catalogue.

Reusing earlier application or documentation results requires Root to prove exact relevant
Source/test/support/toolchain/package/FFI input-closure equality. Changed helper and prose
checks remain actual Native work, with fresh Root HOST documentation confirmation where
applicable. A subsequent replay still requires whole CODE DONE, actual owning CLI exit when
used, known/scoped retirement, separate fresh public idle and fresh Source/runtime/release
admission before real `FINAL0 / OLD-named-semantic1 / restored-FINAL0` with exact restoration.

On 2026-11-19, Root independently accepted that real three-leg proof for
[0e651c6](https://github.com/neuroborus/ward-pulse/commit/0e651c604ddbdc52adbdd86728d9d698a6efbff4).
Both FINAL legs preserved A+B; OLD reached the named late B-only publication failure while
healthy B remained intact. Actual per-leg Java and loaded FFI were qualified. Complete
Source, index, refs, graph and all 95 runtime inputs were exactly restored; custody was
released and Root separately confirmed known controller/leg retirement. Earlier failed
attempts remain failed historical observations, not proof credits.

Fresh HOST verification at that code baseline passed all 947 Flutter tests,
189 cache and 348 widget JVM assertions, both unchanged formatting gates, analysis and
documentation. Root also accepted the normal phone Android build, data-preserving update,
active APK and x86_64 FFI, and the personally viewed unobscured Dashboard original on
2026-11-19. The build used 22305f0; relevant app, core and compiled inputs were qualified
unchanged through 0e651c6. This ordinary startup/artifact acceptance is separate from the
HOST A+B causal proof above and supplies no controlled native A+B UI proof.
This is scoped Original19 evidence, not whole-application acceptance; F1 and effective-plan
recovery (Original20) remain separate open work.

Controlled tests use inert temporary files, injected observations and harmless owned
Python subprocesses. They never substitute canonical Source, execute JVM/provider faults,
launch Flutter, or run `host_replay`. Their scope includes partial writes, durable arming,
byte/mode restoration, locks and identity replacement, PID reuse and surviving readers,
journal bounds/failures, stream/parser contracts (including producer-shaped groups,
loader/setup/named/oracle/teardown traffic and both exact oracle framings), semantic versus
infrastructure outcomes, release admission and failure-evidence privacy. The protected original19 Changeset and
historical evidence remain unchanged; this engineering route adds no product behavior,
dependency, framework, version or release note.
