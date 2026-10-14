# Settings and privacy

Open **Settings** for app-wide refresh, notifications and sync information. Connection keys,
alert thresholds and budget limits are on **Providers**; watch rings are on **Watchface**;
home-widget metrics are on **Widget**.

## Normal Settings controls

| Section | What it shows or changes |
| --- | --- |
| Refresh | Refresh interval while open and approximate background cadence. |
| Notifications | Plan recovery notifications for an exhausted window becoming usable. |
| Diagnostics | Sync timestamp/status and the next Watch summary, when a snapshot exists. |
| Legal | Independent product information. |

Follow [Sync and notifications](/guide/sync) to set the cadence or notification permission.
Diagnostics helps you compare the phone's displayed data and watch summary. It does not
guarantee that the watch has already received a queued update.

Debug builds can also show **Mock data** and **Send to watch**. Those are development controls,
not required steps for normal setup or recovery. Mock figures are demonstration data.

## What stays on the phone

WardPulse stores credentials in secure phone storage. A saved secret is not shown back in
the credential field. It also keeps each connection's last successful normalized snapshot
for recovery; those cached records contain no credentials, prompts or raw provider responses.

Provider requests go directly from the phone to the provider. WardPulse does not operate an
application backend or send usage telemetry to its developer. The watch receives derived
summaries, not your credentials or raw reports. Google Play services can relay those summaries
between paired devices when needed; the [privacy policy](/product/privacy-policy) describes
that transport.

Android backup is disabled for WardPulse's app data. Plan to reconnect providers when moving
to a new installation or device; do not rely on a backup restoring encrypted credentials.

## Remove credentials or reset local data

For one connection, use **Disconnect** or **Remove** on **Providers**, as described in
[Connect providers](/guide/providers#reconnect-change-or-remove-a-connection). Removing it
also prevents obsolete cached data for that connection from being recovered. Revoking an API
key at the provider is a separate action.

For a complete phone reset, use Android's application storage controls for WardPulse. Clearing
app storage removes local credentials, cached data and preferences; you will need to reconnect
and configure the app again. Android's names and path vary by device. There is no WardPulse
**Delete all** button or diagnostic-export control in the current Settings screen.

Do not include keys, cookies, authorization codes, private account data or raw provider payloads
in a help request. [Troubleshooting](/guide/troubleshooting#asking-for-help) lists safer information.

## Source notes

Phone sources are under `apps/phone_flutter/lib/`. Settings, in `settings`:
`settings_screen.dart` (`SettingsScreen`). Connection controls, in `providers`:
`connected_account_dialog.dart` (`ConnectedAccountDialog`) and
`credential_dialog.dart` (`CredentialDialog`). See privacy policy
[phone storage](/product/privacy-policy#data-stored-on-the-phone),
[provider connections](/product/privacy-policy#provider-connections) and
[Wear OS transport](/product/privacy-policy#wear-os); release reference
[privacy and legal](/product/release-checklist#privacy-and-legal).
