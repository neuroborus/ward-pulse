# State and artifact identity

Keep evidence layer-specific. For UI instrumentation, follow [ownership, result and artifact checks](../../../../docs/ANDROID_TOOLCHAIN.md#routine-verification).

## Distinguish the layers

| Layer | Relevant identity/evidence |
| --- | --- |
| Source | Owning commit/dirty content and generator/provider symbols. |
| Generated resources | Exact XML/images produced for that candidate; drift checks. |
| Built artifact | APK/resource hash, package/version code and signing identity. |
| Installed artifact | Actual installed APK/resource identity on the selected target. |
| Active rendition | Current foreground app/page or face renderer's resource package and instance. |
| Effective inputs | Delivered summary/order, provider bindings and live values/TITLE where observable. |

A shared versionName, installed package or successful build does not collapse these into one proof. For WFF,
distinguish the Wear app from the separate legacy/Push face package. An installed newer Push face is not evidence that the active legacy instance uses it.
Static default-provider policy does not prove a retained instance's effective binding.

Record necessary identities before/after the action; never infer an active renderer from the APK most recently built or installed.
Before treating a diagnostic observer as feasible or expanding its harness/matrix, verify actual caller UID/package/context,
service/component and instance scope against pinned official API preconditions/access. Public API does not mean unrestricted cross-package capability.
Use a bounded actual minimal probe where needed; distinguish contract support, observed results and unknown enforcement.
Keep unproved capability Pending: no default/cache substitution, identity swaps, access bypass or unbounded framework growth.
If diagnostics redact live inputs or omit slot mappings, keep them unproved rather than guessing from internal numeric IDs or a resource filename.

For Activity/task claims, inventory unique relevant ActivityRecord identities and task IDs from a complete
current native snapshot. Cross-check relevant top/resumed records; repeated references are not additional
instances. Hold instance-count claims when the dump/projection is incomplete or contradictory, including
a top/resumed owner omitted by the parser, until fresh complete observation resolves it. Keep historical
and fresh inventories separate; later observations do not reconstruct unsupported earlier stage counts.

For claims about which complication slot/type dispatched a tap, shared PendingIntent identity, caller UID,
coordinates or a configured binding alone do not identify the hit. Join actual renderer hit-event evidence to the current
instance/slot, effective provider, current data type and successful destination; DOWN alone is not completed dispatch.
Keep canonical/runtime slot IDs distinct. Resolve retained APK raw XML through its resource table, not a guessed ZIP path,
then join canonical IDs with actual native instance/slot evidence. Numeric IDs alone do not prove that mapping; local proxy
hashes do not prove cross-process token identity. If the join is unavailable, keep type-specific provenance Pending while preserving
separately proved common-entry, navigation/cycle and restoration results.

## Refresh and retained state

Prove the specific surface/binding that needed updating. A request to update all producers
is not a receipt that every bound complication received current data. One provider's
number changing does not prove another split half's TITLE, value or binding refreshed.
Inspect the actual paired halves and possible stale extra-half route after reorder,
selection changes or missing-pair data. Use the owning WFF/provider rules for slot names.

Where possible, distinguish producer output, effective binding and active scene through
supported diagnostics and normal app/renderer operations. A corrected image after scene
recreation supports a stale-layer hypothesis; it does not identify that layer or prove a
durable product fix by itself. Keep unavailable causal evidence Pending.

After an authorized install/update, inspect the whole affected native UI again. Updating only the Wear APK
does not establish that the separately installed face changed, that its active instance refreshed or that old slot bindings were migrated.

After each app/Settings launch, navigation transition or app/face handoff, join current full-window focus,
settled foreground hierarchy and the full first original identifying the expected unobscured page before
the next input or capture batch. For physical targets, use the
[launch/navigation guard](../../android-devices/references/commands.md#guard-launches-and-navigation).
Active wallpaper/renderer mode, UIAutomator idle or launch success alone does not prove compositor handoff.
If a prompt/notification covers the face, stop as an environment obstruction, not Source/UI PASS. Use only safe
existing dismissals; never reset or provision for capture. Inspect previous-page residue through bounded
observations of intended settled content; allow real clock/live-value changes rather than byte-identical frames.
Mixed/transient or obscured frames stay Pending as diagnostics; clean reobservation does not establish a cause or fix.
Fixed sleep alone is insufficient; input/charging procedures stay with android-devices/android-emulators.

For AMBIENT acceptance, prove the actual renderer drawMode and intended visible variant.
Dozing or `isAmbient=true` alone does not distinguish MUTE from AMBIENT; preserve MUTE as
a separate valid case. Do not infer absolute part alpha from Doze screenshot RGB. Use the
owning emulator/device workflow for normal-mode observations without data reset and for
restoring temporary DND state; keep operational commands outside this reference.

After restoring preferences/summary bytes, request the owning normal refresh/reload and
verify the rendered result plus derived caches that can retain data independently. Do
not end restoration at a successful file copy. Preserve existing data and incident proof;
device-preserving operations belong to android-devices/android-emulators, not this skill.

## Case and evidence continuity

While a capture/export session/cell is RUNNING, hold dependent reads/copies/navigation; independent read-only work may continue.
Await that same operation's terminal result before inspection. After failure, safe attributable failed/partial artifacts may be inspected as diagnostics.
Report failed/missing output and allow necessary safe cleanup. Diagnostic inspection needs no capture success and does not establish acceptance.
Acceptance requires success plus the current candidate/file, capture time/hash and actual content; a path, acknowledgement or old file is insufficient.

Keep matched expected/observed states with original native frames/hashes, active instance/binding evidence and capture times.
Separate emulator, physical-device, review-art, fixture and public-image claims. Anonymous display measurements suffice;
retain no credentials, raw provider payloads or unlock/authentication material.

Derive a capture group's window from minimum/maximum measured per-image timestamps, not filenames, array order or one first frame.
Retain the actual timestamp source and timezone; distinguish capture-time observations from file-mtime/export-time evidence.
Export from an explicit indexed source/output list; keep diagnostics separate. Reconcile actual output names, counts and identities
with that cohort before publication. A wildcard match or valid image alone does not prove membership; resolve unexpected outputs.

Scroll each intended current-theme web image into the viewport and confirm its load/dimensions by bounded observation.
Do not await hidden/offscreen lazy variants or infer breakage from their unrequested/incomplete state.

Record healthy demonstrations separately without erasing the incident; verify shared public capture state through user-docs.
A valid fixture cannot compensate for an unproved live binding or establish that a reported incident was fixed.
