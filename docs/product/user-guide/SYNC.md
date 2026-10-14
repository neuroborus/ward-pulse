# Sync and notifications

The phone reads provider data, updates the home widget and sends a derived summary to the
paired watch. Watch and widget displays depend on that phone reporting; they do not independently
sign in to your providers.

## Refresh now

Tap **Refresh** at the top of WardPulse, or pull down on a list. A refresh attempts to read
the connected providers; it cannot make their servers publish data sooner.

The Wear Glance refresh control requests a phone refresh. It can be disabled by the phone's
cadence allowance or by a provider rate limit. **Stale** offers a recovery request; **Rate limited**
means you should wait rather than repeatedly tap. A watch request needs delivery to the phone
and a later summary back, so it is not a guaranteed instant update.

## Set automatic cadence

1. On the phone, open **Settings**.
2. Under **Refresh**, adjust **Refresh interval**.

The selected interval is between 5 and 60 minutes while WardPulse is open; the default is
15 minutes. In the background, the minimum interval is 15 minutes and Android may delay work.
The text beside the slider shows both cadences. Background refresh can run after the phone
app's process has ended, but Android scheduling is not an exact clock.

Provider-side reporting has its own freshness. The Cursor **Team Admin API** may lag about an
hour. This note does not describe the experimental **Cursor plan** connection.

## Offline, failed refresh and restart

After a successful report, WardPulse keeps that connection's normalized data locally. If a
later fetch fails, it can recover those values with their original successful timestamps and
mark them stale. A fresh result for one provider can coexist with retained stale data for another.

This recovery works across phone app restarts and background polling. It does not create data
for a new connection that has never reported successfully, or make provider sign-in and fresh
reporting work without a network. Removed or replaced connections cannot recover their obsolete data.

- The phone can show **Showing previous data** and a provider/sync issue.
- The home widget keeps earlier rows and can show **STALE** after a failed refresh.
- Wear also treats a summary as stale when it is at least two hours old.

These displays can update at different times. The two-hour Wear age rule is not a phone/widget
freshness window, and it does not promise that every complication repaints at the exact boundary.

## Plan recovery notifications

1. Open **Settings → Notifications**.
2. Enable **Plan recovery**.
3. If Android requests notification permission, allow it to receive those notifications.

This feature tells you when a plan window that was exhausted becomes usable again. It is the
notification interruption offered by WardPulse; Dashboard threshold alerts are configured
separately in Providers. Detection depends on reporting and scheduling, so it is not an exact
reset alarm.

If Android blocks notifications, WardPulse reports that. Enable notifications for WardPulse in
Android's app settings, then return to the toggle. Reporting and the in-app Dashboard remain
available without notification permission.

For delayed watch delivery, unchanged figures or failed reports, see
[Troubleshooting](/guide/troubleshooting).

## Source notes

Phone sources are under `apps/phone_flutter/lib/`. Refresh, in `app` and `sync`:
`ward_pulse_app.dart` (`_reload`, `_pullToRefresh`, `_onWatchRefreshRequested`);
`manual_refresh_window.dart` (`ManualRefreshWindow.fromLastSync`). Cadence, in `sync`
and `settings`: `poll_cadence.dart` (`PollCadence.headlessInterval`);
`settings_screen.dart` (`SettingsScreen`, `_setRecoveryNotifications`). Background
surfaces, in `sync` and `widget`: `provider_sync_once.dart` (`providerSyncOnce`),
`phone_widget_sync.dart` (`markExistingRowsStale`). Wear age is in the Wear app's
`app.wardpulse.wear` package: `WatchDashboardSummary.kt`
(`WatchDashboardSummary.isStaleAt`) in `model`. See privacy policy
[cached phone data](/product/privacy-policy#data-stored-on-the-phone), provider reference
[polling cadence](/product/provider-notes#polling-cadence), and Wear reference
[refresh status control](/product/wear-glance-design#refresh-status-control).
