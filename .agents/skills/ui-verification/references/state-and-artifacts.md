# State and artifact identity

Use when proving what is running, especially after app/face updates, ordering changes,
preference restoration or renderer/cache recovery. Keep evidence layer-specific.

## Distinguish the layers

| Layer | Relevant identity/evidence |
| --- | --- |
| Source | Owning commit/dirty content and generator/provider symbols. |
| Generated resources | Exact XML/images produced for that candidate; drift checks. |
| Built artifact | APK/resource hash, package/version code and signing identity. |
| Installed artifact | Actual installed APK/resource identity on the selected target. |
| Active rendition | Current foreground app/page or face renderer's resource package and instance. |
| Effective inputs | Delivered summary/order, provider bindings and live values/TITLE where observable. |

A shared versionName, installed package or successful build does not collapse these into
one proof. For WFF, distinguish the Wear app from the separate legacy/Push face package.
An installed newer Push face is not evidence that the active legacy instance uses it.
Static default-provider policy does not prove a retained instance's effective binding.

Record the identities necessary for the claim before/after the action. Never infer an
active renderer from the APK most recently built or installed. If diagnostics redact live
inputs or do not expose a slot mapping, keep that distinction unproved rather than
guessing it from internal numeric IDs or a resource filename.

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

After an authorized install/update, inspect the whole affected native UI again. Updating
only the Wear APK does not establish that the separately installed face changed, that its
active instance refreshed or that old slot bindings were migrated.

After an app/face handoff, prove current full-window focus and settled native content.
UIAutomator idle or a visible WFF runtime alone does not prove completed compositor handoff;
inspect actual frames for previous-page residue. Use bounded successive observations of
the intended settled content, allowing real clock/live-value changes rather than requiring
universal byte-identical frames. Keep mixed/transient frames Pending as diagnostic evidence;
clean reobservation does not establish a Source cause or product fix. Fixed sleep alone is
insufficient; input/charging procedures stay with android-devices/android-emulators.

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

Keep matched expected/observed states with the original native frames and relevant hashes,
active instance/binding evidence and capture times. Separate emulator, physical-device,
review-art, fixture and public-image claims. Anonymous display measurements are sufficient;
do not retain credentials, raw provider payloads or unlock/authentication material.

Record healthy demonstration data as a separate case without erasing the incident. Verify
shared public capture state through user-docs. A valid fixture cannot compensate for an
unproved live binding or establish that a reported incident was fixed.
