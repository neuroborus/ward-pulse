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

A shared versionName, installed package or successful build does not collapse these into one proof. For WFF, distinguish the Wear app from the separate legacy/Push face package. An installed newer Push face is not evidence that the active legacy instance uses it.
Static default-provider policy does not prove a retained instance's effective binding.
No-clean semantic isolation remains mandatory: prove actual compiled payloads, effective flags, resources and validated signatures; Source BuildConfig, certificate or versionName alone is insufficient. Cross-build signed-APK byte reproducibility is a separate requirement when the task requires it.
A whole-APK hash change triggers scoped inspection, not an automatic code-regression verdict. Retain failed diagnostics and unknown variation cause; equal ZIP payloads do not prove signing-block-only variation. Semantic equivalence must never waive a required byte-reproducibility gate.
Record necessary identities before/after the action; never infer an active renderer from the APK most recently built or installed. Preserve the exact actual built→installed→active SHA-256 identity join; payload equivalence never replaces it.
Before diagnostic stripping, inventory the complete closed footprint, unique names/owners and node/subtree/descendant counts on the unmodified artifact; validate the owning Source's actual predicate, not an error-line/prefix guess.
Removing a parent also removes descendants, so removed-root counts prove neither missing diagnostics nor complete stripping. Handle diagnostic-only wrappers/carriers by closed rules restoring normal structure, then compare WHOLE normal content including renderable literal padding; never silently discard unmatched content.
Before treating a diagnostic observer as feasible or expanding its harness/matrix, verify actual caller UID/package/context, service/component and instance scope against pinned official API preconditions/access. Public API does not mean unrestricted cross-package capability.
Establish the actual OS/API producer of required evidence and its supported type/format/version; a synthetic positive parser fixture proves no producer. Record each field's authority/domain; canonical IDs, observed renderer IDs, provider/system IDs and returned typed/client keys retain their proven domains, without presumed numeric equality or interchangeability.
Apply guards to the actual operation/phase: requester calls require proved system-ID/provider/current active-target identity; independently authorized read-only acquisition/slot reads do not inherit that join unless their contract requires it. Other mutations retain their documented ID/ownership/current-target/custody guards. Distinguish not-invoked, unavailable evidence, denied/rejected, domain-unresolved, forwarded/processed and painted; never infer a later stage from an earlier one.
Use a bounded actual minimal probe where needed; distinguish contract support, observed results and unknown enforcement. Keep unproved capability Pending: no default/cache substitution, identity swaps, access bypass or unbounded framework growth. Redacted inputs/missing mappings stay unproved; no guessed internal numeric IDs or resource-filename joins.

For Activity/task claims, inventory unique relevant ActivityRecord identities and task IDs from a complete current native snapshot. Cross-check relevant top/resumed records; repeated references are not additional instances. Hold instance-count claims when the dump/projection is incomplete or contradictory, including a top/resumed owner omitted by the parser, until fresh complete observation resolves it. Keep historical and fresh inventories separate; later observations do not reconstruct unsupported earlier stage counts.

For claims about which complication slot/type dispatched a tap, shared PendingIntent identity, caller UID, coordinates or a configured binding alone do not identify the hit. Join actual renderer hit-event evidence to the current
instance/slot, effective provider, current data type and successful destination; DOWN alone is not completed dispatch.
Keep canonical/runtime slot IDs distinct. For raw resources, bind each lookup to the exact APK bytes and resolve the requested route through that variant/embedded APK's own resource table BEFORE EACH ZIP read, including batched measurements; reuse only a route bound to identical bytes, never infer archive-path equality from a shared logical name such as raw/watchface. Never transfer debug/Legacy ZIP paths to release/Push.
Read metadata from the exact owning element and named field VALUE in its actual emitted representation; nearby IDs/substrings or assumed encoding are not attribute proof. Parser failure stays Unknown, never an inferred default.
Before asserting identity, retain bounded variant and expected-versus-observed resource-route facts. Bind asset membership/counts to exact operation-approved names and record the full archive inventory separately; broad prefix/glob count alone does not establish selected-catalog membership/cardinality. Missing lookup stays Pending; no guessed alternative paths or raw sensitive dumps.
Join canonical IDs with actual native instance/slot evidence; numeric IDs alone do not prove that mapping, and local proxy hashes do not prove cross-process token identity.
If the join is unavailable, keep type-specific provenance Pending while preserving separately proved common-entry, navigation/cycle and restoration results.

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

Before an installer/device recipe touches a protected artifact cohort, inspect expanded commands, aggregate task/module installs AND possible implicit platform updates from bundled/default assets; reconcile EVERY affected package with the authorized phase, not only the main APK.
Hold unreconciled module/package or implicit-update effects; use a supported scoped owner route or return the recipe/provisioning finding to actual Runner. Do not assume a narrower task prevents platform reactions.
Record actual affected installed versions/hashes before and after; unexpected advancement remains a failed preservation gate/gap, never a UI Update witness inferred from test success. Keep cause unproved unless established independently; task membership or installer attribution alone is insufficient.
After an authorized install/update, inspect the whole affected native UI again. Updating only the Wear APK
does not establish that the separately installed face changed, that its active instance refreshed or that old slot bindings were migrated.

After each app/Settings launch, navigation transition or app/face handoff, join current full-window focus and settled foreground hierarchy with the full first original identifying the expected unobscured page.
Return/view the actual image to the model and evaluate it BEFORE the next screen-dependent decision, input, mutation or capture batch, including ordinary planned prefix continuation; queuing view_image/image and those actions inside one functions.exec is not inspection.
Independent read-only batching and unconditional necessary failure-safe cleanup/recovery need no image gate; ordinary planned prefix progression is not this exception. Recovery establishes neither image inspection/PASS nor permission for further case advance. For physical targets, use the
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

An awaited tool can return a RUNNING session/cell marker; inspect the actual returned marker and terminal status BEFORE dispatching dependent reads/copies/navigation, even inside one orchestration script.
While RUNNING, hold dependencies; independent read-only work may continue. Await that same operation's terminal result. After failure, safe attributable failed/partial artifacts may be inspected as diagnostics.
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
