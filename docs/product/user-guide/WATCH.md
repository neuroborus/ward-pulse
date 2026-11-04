# Watch and watch face

The Wear app shows a compact usage summary from your phone. The optional WardPulse face
adds remaining-capacity rings. Connect providers and set budgets or alert rules on the phone.

## Set up the watch

1. Pair the watch with your phone using its manufacturer's normal setup. Check that its
   companion app reports it connected.
2. Connect a provider on the phone, then refresh **Dashboard**.
3. Open WardPulse from the watch's app launcher and allow the summary to arrive.

Until its first valid phone summary, Wear shows a setup prompt. You do not enter keys or
sign in to providers on the watch. If the phone has data but the watch does not, follow
[Troubleshooting](/guide/troubleshooting#watch-summary-is-missing-or-old).

## Read the Wear app

**Glance** shows remaining capacity with provider labels, compact tracks, optional purchased
credits and refresh status. A title such as **Claude plan · Weekly** names the plan and its
selected window. Paired **Cursor / Others**, **Codex plan** or **Claude / Fable** rows show two
percentages, with the inner half first.
Glance hides the clock to make room for larger labels. The clock remains on **Plan windows**,
**Alerts**, the **Watch face** setup screen and the prompt shown before the first summary.

Tap the WardPulse name or a usage complication on the face to open Glance. Before the first
summary, this opens **Sync from phone**. Returning through the watch's app launcher keeps
your current page. Swipe right or press Back from **Alerts** or **Watch face** to return to
the previous page; from either home page, one dismissal leaves the app.

![Clock-free Wear Glance showing selected plan capacity and available purchased credits.](/screenshots/wear-glance-overview.png)

The selected metric with the lowest remaining percentage appears first.
This general Glance example uses demo usage data. The **Mock data** line identifies the
demonstration; see the [refresh status legend](#refresh-status) for the control's colours and actions.

### Plan windows

Swipe upward to the second page, **Plan windows**, to see reported windows and when they
return. Exhausted windows appear first. Within each group, upcoming resets appear soonest
first; missing or overdue reset times follow. Reset times may be unavailable.

With larger text, the Glance legend may scroll. Swipe within the legend to reach its remaining
rows; start outside the legend to change pages. Refresh and Alerts stay in place.

![Plan windows showing a reported usage window and its reset time.](/screenshots/wear-plan-windows.png)

Reset times belong to their reported windows and may differ between windows.

### Alerts and refresh

Tap **Alerts: N** on Glance when N is greater than zero to open the active alert list.
**Alerts: 0** is disabled. If the list was already open when its last alert cleared, it shows
**No active alerts**. The count describes alerts, not whether every provider freshly synced.
Configure rules on the phone's **Providers** tab; Wear has no rule editor.

#### Refresh status

**OK** means there is no detail message. **!OK** directs you to the line below; it does not
always mean an error.

Green **OK** and amber/orange **!OK** can be tapped to request a phone refresh. Grey/dim
**OK** or **!OK** cannot be tapped. Grey **OK** can be a normal wait before the phone permits
another refresh.

Only one detail is shown. The control can be grey even when **Stale**
appears below it, if a refresh wait or rate limit also applies. **OK** does not confirm
that every provider is current or that a refresh reached the phone.

| Message | Meaning and action |
| --- | --- |
| **Stale** | Earlier data needs a newer report. Check the phone and connectivity; refresh when allowed. |
| **Rate limited** | A provider is temporarily limiting requests. Wait before trying again. |
| **Auth required** | Sign-in or a saved key needs attention. Reconnect under **Providers** on the phone. |
| **Warning** | The summary reports a warning. Check the phone's Dashboard and active alerts. |
| **Error** | A reporting attempt failed. Open the phone's Dashboard for details and recovery. |
| **Unknown** | The summary's status is unavailable. Check reporting on the phone. |

![Clock-free Wear Glance showing amber !OK, Stale and disabled Alerts: 0 in a circular screen.](/screenshots/wear-glance.png)

This example shows amber **!OK** with **Stale**: the saved summary needs a newer report.
**Alerts: 0** is disabled because there are no active alerts.

If **Ring data unavailable** replaces the rows, none of the selected rings has displayable
data. Check the phone's Dashboard and [ring choices](#choose-usage-rings).

Wear can mark a received summary stale after two hours without a newer summary.
See [Sync and notifications](/guide/sync#refresh-now) for request delivery and refresh timing.

## Choose usage rings

1. On the phone, open **Watchface**.
2. Under **Ring slots → Wear & watch face**, select the known metrics you want.
3. Read the count of used slots. The limit is three bands and at most two paired bands.
   Selecting both halves of a supported Codex/Spark, Cursor or Claude/Fable pair shares one
   band, so the count can differ from the number of checked rows. Either half alone uses
   an ordinary band.
4. If a choice is disabled, read its reason. Free another band or break another pair as
   needed before adding it. An unavailable metric separately explains its missing percentage.
5. Check **Next watch payload**, then allow the updated summary to reach Wear.

![Watchface metric selection showing shared ring choices in the light theme.](/screenshots/phone-watch-settings-light.png)

![Watchface metric selection showing shared ring choices in the dark theme.](/screenshots/phone-watch-settings-dark.png)

This selection uses demo usage data; supported paired metrics share a band.

Console organization and Cursor Team **Today**, **Week** and **Month** budget choices use
remaining percentages. Each needs known spend, a positive cap in the same currency and a
usable percentage. Missing spend or a missing/unusable cap is not a full or empty ring.
Set a local cap under **Providers → Budget limits**; it does not enforce provider spending.
These calendar periods begin at midnight UTC, Monday UTC and the first calendar day UTC.
They do not supply a Plan reset time. Purchased Extra usage/on-demand meters stay off watch
rings; their widget eligibility is separate.

Until you make a selection, defaults admit available metrics in catalogue order within both
limits. Clearing every checkbox is an explicit choice to show no rings.

If saved choices exceed either limit, **Correct ring choices** keeps them visible for you to
remove. Selected unavailable or no-longer-reported choices can still be deselected, even if
more than one removal is needed. Additions that exceed a limit are not saved. Watch updates
pause and keep the last published summary until your choices fit; phone Dashboard and widget
updates continue.

Choose which metrics fill the bands; paired pools can share one band.
With both the watch app and face updated, one or two available bands widen automatically
as fewer bands are shown. A single band leaves more open space toward the centre than
two bands; three bands keep their current widths. A pair counts as one
band. Temporarily unavailable data can change the width when it disappears or returns;
a known exhausted **0%** still occupies its band. An older app or face keeps narrow bands
until both are updated.

These examples use the same demo readings with different ring selections.

![One widened band with a single selected usage metric.](/screenshots/wear-watch-face-one-band.png)

**One band:** one selected metric uses a wider band.

![Two widened bands including paired usage readings.](/screenshots/wear-watch-face-two-bands.png)

**Two bands:** the bands widen, while paired readings keep their inner/outer identities.

### Display order

Among selected known metrics, the lowest remaining percentage appears first on Glance and
closest to the centre on the [face](#select-and-customize-the-face). Outside-to-inside bands
move toward less capacity left.
Order changes with usage; the phone picker chooses metrics, not display order.
A shared band uses the lower remaining percentage of its two halves for its position.
Codex's main pool, Cursor Models or ordinary Claude keeps the left/inner half; Spark,
Other Models or Fable keeps the right/outer half. Usage changes never swap these identities.

Claude plan windows use the tightest known window, including an exhausted zero. The phone
Dashboard still lists the individual windows. For an unpaired ordinary Claude row, the Glance title keeps the chosen window's
name: **5h**, **Weekly**, **Opus weekly** or **Sonnet weekly**. A selected exhausted metric
keeps a grey empty track and pale-red **0%** token; it is not replaced by a less-used window.
Tiny positive values rounded to zero keep ordinary styling.

**Claude plan** uses those ordinary windows; **Claude · Fable** is a separate included weekly
sub-cap when reported. Selecting both produces **Claude / Fable**. Fable uses warm red
with an orange tint (`#FF603D`); ordinary Claude keeps `#E8915A`. A missing percentage stays
unknown: only known halves fill rings, and a surviving half uses an ordinary band. Reported
resets stay with their own windows on **Plan windows**.

**Next watch payload** describes what the phone will send; it is not delivery confirmation.
Ring choices are independent of the phone's [home-widget selection](/guide/widget).

## Select and customize the face

The WardPulse face requires **Wear OS 5 or later**. The dashboard app can run on Wear OS 4;
the face cannot be installed there.

For direct APK downloads, `WardPulse-V-WearOS.apk` installs the watch app;
`WardPulse-V-WatchFace-WearOS5Plus.apk` installs the separate face. V is the release version.
The technical `wardpulse-push-…apk` is bundled with the watch app, not another direct
installer to choose.

Open WardPulse on the watch. From **Glance**, swipe up to **Plan windows**, scroll past the
windows and tap **Watch face**. Before the first phone summary, tap the **Watch face** button
below **Sync from phone**. Swipe back to return to the previous screen.

On supported Wear OS 6+ devices, the face can be installed with the Wear app. If it is
missing, tap **Install watch face**. Installation does not activate it. If another face
occupies the available slot, WardPulse leaves it alone. **Check again** refreshes status
without installing or activating anything.

Tap **Use watch face**, when offered, to replace your current face with WardPulse. It may
ask for permission once. If you decline, dismiss the request or cannot use that action,
select WardPulse manually:

> Touch and hold your current watch face, then find WardPulse in the watch-face list.

![Historical watch face setup example showing manual-selection guidance after declining activation.](/screenshots/wear-watch-face-utility.png)

Historical manual-selection example after declining activation; choose WardPulse from the
watch-face list.

WardPulse will not switch back after you choose another face. **In use** reports a checked
current selection; **Installed** confirms installation, not selection.

If **Update watch face** appears, tap it to update the bundled face. Your face selection and
customizations are preserved. Updating the Wear app alone does not update the installed
face. The face update does not request activation permission. **Try again** after an
installation or update error repeats only that operation.

On Wear OS 5, or another compatible watch without bundled installation, install WardPulse
Watch Face separately only if needed. The **Watch face** utility confirms when the separate
face is installed, explains when installation is needed, or says it could not check. Tap
**Check again** for a fresh result. Returning from an external installation or reopening the
utility also refreshes the result; you do not need to clear data or reinstall the Wear app.

Select WardPulse through your watch's available system or companion watch-face selector.
On OnePlus Watch 2, select WardPulse in OHealth. Other brands may use a different selector.
Installation alone does not confirm the face is in use or that an update
is available. The existing face, settings and data are preserved. The historical
permission-decline image above does not illustrate this separate-installation check.

![WardPulse circular watch face with the selected usage bands and populated default upper cells.](/screenshots/wear-watch-face.png)

This face and the general Glance example use the same demo data and ring selection. Shared
bands show separate remaining percentages; purchased credits appear where applicable. The
upper cells show the day, temperature and UV index.

The three upper complication cells are customized in the **system watch-face editor**. Open
the watch's edit/customize action for WardPulse and select an upper cell to choose an available
complication provider. Exact controls and available providers vary with the watch's system.
These cells are separate from the usage rings selected in the phone's Watchface tab.

Choose compact text or a monochrome icon, shown in the face's text colour. Provider text takes
priority; a range value without text falls back to its raw number, without guessed units or a
percentage conversion. Extra titles and companion icons are not shown beside text, so units
must be included in the provider's text. These small cells may shorten longer content to fit.
Providers that offer only long text or photos are not offered. If important meaning is missing,
choose another provider.

In the same editor, **Temperature** offers **Auto**, **Celsius (°C)** and **Fahrenheit (°F)**.
Auto is the default and keeps the watch's built-in weather unit. Celsius or Fahrenheit converts
that built-in reading to whole degrees when its source unit is known. An unrecognized source
unit keeps the original number with a degree sign; unavailable weather leaves the empty recess.

Leave the middle upper cell unassigned to see the face's built-in temperature. If you assign a
weather complication there, its provider supplies the displayed text and covers the built-in
reading. **Temperature** does not change that provider's units; use the provider's own settings
where available. Clearing the assignment reveals the built-in reading again when weather is available.

Choose usage rings on the phone. Watch weather and other system complications depend on
their own available data; refreshing provider usage does not itself update watch weather.
