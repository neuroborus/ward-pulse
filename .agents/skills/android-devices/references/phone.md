# Physical phone

Use the connection reference to establish the exact target before operating it. Respect
the owner's current use: if the phone was taken away or is unavailable, continue work
that does not need it and leave physical-phone acceptance pending. A watch can remain
available independently; do not claim the phone must stay connected for every watch task.
Use [command templates](commands.md) for the needed existing ADB operations.

Check the current visible screen and keyguard before input. Keep navigation within the
requested app/setup scope; do not inspect unrelated private apps or dismiss private
notifications to manufacture a clean test screen.
Use existing visibility-only OS controls for documentation captures and restore temporary
theme/status changes. Apply user-docs for actual theme pairs, clean launcher/dock and privacy.

For an authorized WardPulse update, compare installed/candidate package and signing
certificate before `adb -s <verified-serial> install -r <apk>`. A certificate mismatch is
not permission to uninstall or replace a signed release with an incompatible debug build.
Preserve accounts, credentials, app data, pairing and scheduled jobs. Do not use force-stop
as routine app restart; if a scoped restart is necessary, prefer the existing safe
background/`am kill` flow and verify that the old process actually retired.

Use normal UI and supported ADB inspection. Release builds can reject `run-as`; report
that boundary rather than rooting the device, changing its build or bypassing storage.
Capture only the requested app state. Do not publish authentication, unlock or identifying
frames, and do not represent emulator-only results as physical-phone verification.
