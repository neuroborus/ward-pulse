# Settings and privacy

Open **Settings** for app-wide refresh, notifications and sync information. Connection keys,
alert thresholds and budget limits are on **Providers**; watch rings are on **Watchface**;
home-widget metrics are on **Widget**.

## Settings controls

| Section | What it shows or changes |
| --- | --- |
| Refresh | Refresh interval while open and approximate background cadence. |
| Notifications | Plan recovery notifications for an exhausted window becoming usable. |
| Diagnostics | Sync timestamp/status and the next Watch summary, when a summary is available. |
| Help | User guide in your external browser. |
| Legal | Independent product information. |

Follow [Sync and notifications](/guide/sync) to set the cadence or notification permission.
Diagnostics helps you compare the phone's displayed data and watch summary. It does not
guarantee that the watch has already received an update.

Choose **Settings → Help** to open the user guide in your external browser.

## Stored data and provider requests

WardPulse stores credentials encrypted in secure phone storage and uses them to authenticate
requests directly to the matching provider. A saved secret is not shown back in the credential
field. The app also keeps each connection's last successful usage data for recovery; those
records contain no credentials, prompts or raw provider responses.

WardPulse does not operate an application server or send usage telemetry to its developer.
The watch receives compact summaries, not your credentials or raw reports. Google Play services
can relay those summaries between paired devices when needed; the
[privacy policy](/product/privacy-policy) describes that transport.

Android backup is disabled for WardPulse's app data. Plan to reconnect providers when moving
to a new installation or device; do not rely on a backup restoring encrypted credentials.

## Remove credentials or reset local data

For one connection, use **Disconnect** or **Remove** on **Providers**, as described in
[Connect providers](/guide/providers#reconnect-change-or-remove-a-connection). Removing it
also prevents obsolete stored data for that connection from being reused. Revoking an API
key at the provider is a separate action.

For a complete phone reset, use Android's application storage controls for WardPulse. Clearing
app storage removes local credentials, stored data and preferences; you will need to reconnect
and configure the app again. Android's names and path vary by device. There is no WardPulse
**Delete all** button in Settings.

Do not include keys, cookies, authorization codes, private account data or full provider
responses in a help request. [Troubleshooting](/guide/troubleshooting#asking-for-help)
lists safer information.
