# Sync and notifications

The phone reads provider data, updates the home widget and sends a compact summary to the
paired watch. Watch and widget displays depend on that phone reporting; they do not sign
in to your providers independently.

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
The text beside the slider shows both cadences. Background refresh may continue when you
are not using WardPulse, subject to Android scheduling.

Provider reporting has its own freshness. The Cursor **Team Admin API** may lag about an
hour. This note does not describe the experimental **Cursor plan** connection.

## Offline, failed refresh and restart

After a successful report, WardPulse keeps that connection's data locally. If a later
refresh fails, it can show those values with their original successful timestamps and
mark them stale. A fresh result for one provider can coexist with earlier stale data for another.

This recovery works across phone app restarts and background polling. A new connection
that has never reported successfully has no earlier data to recover. Provider sign-in and
fresh reporting need network access. Removed or replaced connections cannot reuse obsolete data.

- The phone can show **Showing previous data** and a provider/sync issue.
- The home widget keeps earlier rows and can show **STALE** after a failed refresh.
- Wear also treats a summary as stale when it is at least two hours old.

These displays can update at different times. The two-hour rule applies to Wear, not the
phone or widget, and a watch display may update after that time rather than exactly then.

## Plan recovery notifications

1. Open **Settings → Notifications**.
2. Enable **Plan recovery**.
3. If Android requests notification permission, allow it to receive those notifications.

This feature tells you when a plan window that was exhausted becomes usable again. It is
WardPulse's notification feature; Dashboard threshold alerts are configured separately in
Providers. Detection depends on reporting and scheduling, so it is not an exact reset alarm.

If Android blocks notifications, WardPulse reports that. Enable notifications for WardPulse in
Android's app settings, then return to the toggle. Reporting and the in-app Dashboard remain
available without notification permission.

For delayed watch delivery, unchanged figures or failed reports, see
[Troubleshooting](/guide/troubleshooting).
