# Sync and notifications

The phone reads provider data, updates the home widget and sends a compact summary to the
paired watch. Watch and widget displays depend on that phone reporting; they do not sign
in to your providers independently.

## Refresh now

Tap **Refresh** at the top of WardPulse, or pull down on a list. A refresh attempts to read
the connected providers; it cannot make their servers publish data sooner.

On Wear Glance, an active **OK** or **!OK** control can request a phone refresh. A grey
control is unavailable, even when **Stale** appears below it. See the [refresh status legend](/guide/watch#refresh-status)
for colours, messages and actions.

A watch request needs delivery to the phone and a later summary back, so it is not a
guaranteed instant update.

## Set automatic cadence

1. On the phone, open **Settings**.
2. Under **Refresh**, adjust **Refresh interval**.

The selected interval is between 5 and 60 minutes while WardPulse is open; the default is
15 minutes. In the background, the minimum interval is 15 minutes and Android may delay work.
The text beside the slider shows both cadences. Background refresh may continue when you
are not using WardPulse, subject to Android scheduling.

Provider reporting has its own freshness. Cursor aggregates team usage by the hour, so a
successful refresh can return unchanged figures. This applies to **Team Admin API**,
separately from the experimental **Cursor plan** connection. See [Cursor reporting history](/guide/providers-cursor#read-the-history).

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

## Alert notifications

1. On **Providers**, configure the usage or budget alert thresholds you want.
2. Open **Settings → Notifications → Alert notifications** to control delivery.
3. Allow Android's notification request when it appears. If **Notifications are blocked** appears
   in Settings, choose **Enable notifications** to open WardPulse's Android settings,
   allow notifications there, then return to WardPulse. Turning a WardPulse delivery switch
   off and back on can retry the request; Android decides whether to show it again.

Alert notifications and **Plan recovery** are independent and start on unless you saved Off.
They share one Android permission. On the first eligible foreground use, WardPulse makes one
automatic attempt after reading your choices and becoming ready on screen. Either switch
being on qualifies; saving both off suppresses the attempt. A denial does not cause repeated
automatic prompts after refresh or restart. Existing installations can receive this one
bootstrap attempt too, subject to Android's previous permission decisions.

Android can block delivery even while a WardPulse switch is on. Denial keeps your saved
choices; an explicit off-to-on retry reports blocking. Polling and background delivery never
request permission. WardPulse registers its **Alert notifications** and **Plan recovery**
system channels before any notification; their blocking and importance remain under Android's
controls. The location and appearance of those controls vary by Android version and device.

An enabled threshold can notify when first observed crossed. Unchanged crossings are suppressed
across app restarts; a report showing the condition clear rearms it. Missing or unknown data does
not rearm it. Changing a rule or disabling/re-enabling it while it remains crossed does not
replay the notification. Crossings seen while muted or denied are not queued for later delivery.
Provider errors alone do not trigger these notifications. Delivery is best effort: a failed
attempt can be lost, and overlapping background/foreground work can repeat an attempt.

Turning either delivery switch off leaves reporting, in-app alerts, watch/widget updates and
recovery tracking active. Notification text contains only the provider family, window or budget
name, and the configured alert boundary in **% left** or recovery copy. An alert set to 20% left
still says 20% left when a later report shows 10% left. Check Android's lock-screen settings for
visibility.

## Plan recovery notifications

1. Open **Settings → Notifications**.
2. Enable **Plan recovery**.
3. If Android requests notification permission, allow it to receive those notifications.

This feature tells you when a plan window that was exhausted becomes usable again. It is
independent of Alert notifications and needs no threshold rule. Detection depends on reporting
and scheduling, so it is not an exact reset alarm or an exactly-once delivery guarantee.

The **Notifications are blocked** warning applies to both switches, including saved Off choices.
**Enable notifications** opens Android settings; it does not grant permission or change either
switch. WardPulse rechecks when you return. Android's channel settings and Do Not Disturb can
still limit delivery without this warning. Reporting and the in-app Dashboard remain available
without notification permission.
Android may bridge phone notifications to a paired watch; WardPulse does not guarantee mirroring.

For delayed watch delivery, unchanged figures or failed reports, see
[Troubleshooting](/guide/troubleshooting).
