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
HOST also owns fresh locked FFI build/load qualification, the existing five-file focused
absence command, unchanged complete `just check-phone`, documentation confirmation,
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
  SHA-256 of `encoded(tree_seal(path))`;
- `ffiSha256`, the content hash of the qualified unchanged
  `core/target/debug/libward_pulse_ffi.so`.

Inputs must cover the pinned SDK, all named executables, the actual package-config
file, every external or SDK package root that config names, and the FFI artifact. Directory
seals include membership, regular-file contents/modes/identities and symlink identities
and targets without traversing them. Root must include separately resolved toolchain
or package inputs reached through symlinks; `Runtime` rejects unsealed link targets.
It verifies SDK version metadata without invoking a writing SDK wrapper.
The new controller independently binds its own script, interpreter, PID/start and boot
identity. It also verifies its script against the released commit's immutable blob.

## Replay and custody

`Git` disables optional writes and replacement objects. `Custody` exclusively creates
the canonical `.git/index.lock` before mutable state is sealed. An existing lock is
left untouched. Git launch, identity capture and stream setup share an owned-process
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

`Reporter` reads the real raw `connection absence ownership oracle ` line alongside
reporter JSON. Exactly one oracle must occur while the named test is active. Account
objects retain `id`, `connection`, `status`, nullable `spent` and allowance observations.
Completed absence reads, account order, healthy B, accepted A+B publication, late outcome,
actual publication and redraw/readback values are established before classifying flags
or assertions. FINAL must exit 0 with successful reporter completion and preserved A+B.
OLD must exit 1 at the named late-publication assertion, after accepted A+B actually
becomes late B-only publication and redraw. After verified exact restoration, restored
FINAL must exit 0 and preserve A+B. Earlier assertions, setup, compilation, FFI loading,
transport, timeout or missing evidence are infrastructure/validity failures, never RED.

The parser bounds UTF-8, 64 KiB lines, 4 MiB stdout, 4 MiB stderr, nesting and retained
evidence. It rejects duplicate keys, duplicate or unassociated oracles, malformed
JSON, wrong required types and nonfinite numbers. Repeated reporter event types and
legitimately nullable locations or oracle values remain valid. `seals.json`, the journal
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

## Native controlled regressions and check ownership

The complete corrective plan's inventory remains four commands, all from the canonical
repository root, **only in FINALIZE**:

| Command | Commit | Executor |
| --- | --- | --- |
| `git diff --check HEAD` | 1, 2 | Ordinary Worker |
| `python3 -B -m unittest discover -s tools/test-phone-cache -p 'test_*.py'` | 2 | Selected Runner-trusted vector, scratch only |
| `just check-docs` | 2 | Ordinary Worker; writes generated docs beside Source |
| `just release-status` | 2 | Selected Runner-trusted vector, scratch/cache |

FIRST Worker/Reviewer DISCOVERY inventories applicability, actual capabilities and observed
blockers without executing these checks. Root independently qualifies the merged schedule,
step assignments and each current subset by exact command identity. The command-specific
executor assignments above correct the plan's generic trusted-vector sentence; none of the
four checks is dropped or moved to HOST. Implementation and semantic review confer no
FINALIZE credit. Selected trusted commands never execute inside an agent turn.

Controlled tests use inert temporary files, injected observations and harmless owned
Python subprocesses. They never substitute canonical Source, execute JVM/provider faults,
launch Flutter, or run `host_replay`. Their scope includes partial writes, durable arming,
byte/mode restoration, locks and identity replacement, PID reuse and surviving readers,
journal bounds/failures, stream/parser contracts, semantic versus infrastructure outcomes,
release admission and failure-evidence privacy. The protected original19 Changeset and
historical evidence remain unchanged; this engineering route adds no product behavior,
dependency, framework, version or release note.
