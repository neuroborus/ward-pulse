# Physical Wear OS watch

Use the connection reference for the current transport and verified hardware identity.
Wireless connection ports may change while the watch's DHCP address stays the same.
Phone and watch pairing is separate from their ADB connection; do not reset either pairing
as a routine recovery. A phone being absent does not prevent independent watch UI work.
Use [command templates](commands.md) for bounded ADB inspection, input and capture.

## Lock and charging

A visible face, resumed WardPulse Activity or battery percentage does not establish that
the watch is unlocked or its app visible. Inspect actual keyguard/foreground state and
the rendered frame immediately before the scenario. Charging SystemUI can cover the app;
verify actual charging and visible UI rather than assuming that placement on the charger
or a foreground record proves the test state. Follow the state-dependent
[charging workflow](charging.md) before treating charging as a blocker or asking the owner
to remove the watch from its charger.

Use only the owner's explicitly authorized pattern/PIN; store it only if the owner
requested storage. Keep the secure lock enabled. Recheck the current unlock grid/UI
geometry; do not reuse cached coordinates blindly. For a pattern, use one continuous
gesture, issue a final MOVE through the last intended node before UP, and release there.
Persist an explicitly owner-requested unlock secret only in the ignored mode-600 `.env`.
Keep the sequence, derived pixel paths and authentication frames out of logs, proofs,
examples and delegated-agent context; never save a frame with the pattern path visible.
After rejection, stop automated input and inspect the cause; existing authorization
persists. Never guess or retry in a loop. Verify actual unlocked state before continuing.

Perform unlock, app navigation and scenario observation in one bounded operational
sequence. A model round trip can outlast the short lock timeout; recheck keyguard before
the next scenario rather than interpreting nonresponsive taps as an app failure. A locked
complication displaying `--` does not establish missing or lost provider data.

## App and face checks

Use normal UI/supportable ADB operations; a signed release can reject `run-as`. Do not use
adb root, disable security or replace release data to obtain a private inspection path.
For an authorized update, verify package/signing identity and install in place with `-r`.
Preserve the selected face, complication choices, summary data, pairing and scheduled jobs.
Do not apply emulator reset/system-UI recovery commands to the physical watch by analogy.

Distinguish real face taps, launcher entry, Home and ordinary dismissal when testing app
navigation. Record bounded Activity/task and visible-route observations; diagnostic app
launches can create retained instances and contaminate a subsequent back-stack scenario.
Restore temporary navigation/OS state without erasing data. Public capture additionally
follows user-docs, including actual default data in every upper face cell.
