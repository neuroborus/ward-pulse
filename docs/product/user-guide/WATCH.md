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
credits and refresh status.

![Wear Glance showing selected capacities in a circular screen.](/screenshots/wear-glance.png)

The selected metric with the lowest remaining percentage appears first.
The example has a grey **OK** control and disabled **Alerts: 0**.

### Plan windows

Swipe upward to the second page, **Plan windows**, to see reported windows and when they
return. Exhausted windows appear first. Within each group, upcoming resets appear soonest
first; missing or overdue reset times follow. Reset times may be unavailable.

![Plan windows showing a reported Claude window and its available reset time.](/screenshots/wear-plan-windows.png)

A reported plan window with its available upcoming reset time.

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

If **Ring data unavailable** replaces the rows, none of the selected rings has displayable
data. Check the phone's Dashboard and [ring choices](#choose-usage-rings).

Wear can mark a received summary stale after two hours without a newer summary.
See [Sync and notifications](/guide/sync#refresh-now) for request delivery and refresh timing.

## Choose usage rings

1. On the phone, open **Watchface**.
2. Under **Ring slots → Wear & watch face**, select the known metrics you want.
3. Read the count of used slots. The limit is three bands; some supported Codex/Cursor pairs
   share a band, so the count can differ from the number of checked rows.
4. Deselect an existing band choice first only if your desired choice is disabled because all
   three bands are full. The other half of an already selected pair may remain available
   without using another band. Separately, an unavailable metric explains its missing percentage.
5. Check **Next watch payload**, then allow the updated summary to reach Wear.

![Watchface selection showing three bands used by checked metrics in the light theme.](/screenshots/phone-watch-settings-light.png)

![Watchface selection showing three bands used by checked metrics in the dark theme.](/screenshots/phone-watch-settings-dark.png)

Choose which metrics fill the bands; paired pools can share one band.

### Display order

Among selected known metrics, the lowest remaining percentage appears first on Glance and
closest to the centre on the [face](#select-and-customize-the-face). Outside-to-inside bands
move toward less capacity left.
Order changes with usage; the phone picker chooses metrics, not display order.
A shared Codex/Cursor band uses the lower percentage of its two pools for its position.
Codex's main pool or Cursor Models keeps the left/inner half; Spark or Other Models keeps
the right/outer half.

Claude plan windows use the tightest known window, including an exhausted zero. The phone
Dashboard still lists the individual windows. On Glance, a selected exhausted metric keeps
a grey empty track and pale-red **0%** token; it is not replaced by a less-used window.
Tiny positive values rounded to zero keep ordinary styling.

**Next watch payload** describes what the phone will send; it is not delivery confirmation.
Ring choices are independent of the phone's [home-widget selection](/guide/widget).

## Select and customize the face

The WardPulse face requires **Wear OS 5 or later**. The dashboard app can run on Wear OS 4,
but the face cannot be installed there.

On the watch, swipe to **Plan windows**, scroll past all windows and tap **Watch face**.
Before the first phone summary, the same entry is below **Sync from phone**. This opens a
setup screen; swipe back to return to the dashboard.

On supported Wear OS 6+ devices, the face can be installed together with the Wear app. If
it is missing, tap **Install watch face**. Installation does not change your current face.
If another face occupies the available slot, WardPulse leaves it alone; use **Check again**
after a slot is free. **Check again** also retries a failed status check without installing
or activating anything.

When offered, tap **Use watch face** to make WardPulse your current face. This replaces
your current face and may ask for permission once. If you decline or dismiss permission,
or activation is unavailable or was already attempted, select it manually:

> Touch and hold your current watch face, then find WardPulse in the watch-face list.

WardPulse will not switch back after you choose a different face. **In use** means the
current face was checked; an installation or update alone reports **Installed**.

If **Update watch face** appears, tap it to apply the newer bundled face. Updating the Wear
app alone does not update an installed face. The face update preserves its settings and
your current face selection; it does not request activation permission. **Try again** after
an installation or update error retries only that operation.

On Wear OS 5 or other supported watches without bundled installation, install WardPulse
Watch Face separately, then select it from your watch-face list. The existing separately
installed face and its settings are preserved.

![WardPulse circular watch face with selected usage bands and upper complications.](/screenshots/wear-watch-face.png)

The lowest selected remaining percentage fills the innermost band; upper cells show watch
complications.

The three upper complication cells are customized in the **system watch-face editor**. Open
the watch's edit/customize action for WardPulse and select an upper cell to choose an available
complication provider. Exact controls and available providers vary with the watch's system.
These cells are separate from the usage rings selected in the phone's Watchface tab.

Choose usage rings on the phone. Watch weather and other system complications depend on
their own available data; refreshing provider usage does not itself update watch weather.
