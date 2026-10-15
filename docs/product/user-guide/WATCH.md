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

The refresh control sends a request to the phone. Cadence and rate-limit states can disable
it; **Stale** indicates recovery is needed. See [Sync and notifications](/guide/sync).
Wear can mark a received summary stale after two hours without a newer summary.

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

The WardPulse face is a separate installed package and requires **Wear OS 5 or later**.
Use the watch's normal face picker to select WardPulse after installing its compatible build.

![WardPulse circular watch face with selected usage bands and upper complications.](/screenshots/wear-watch-face.png)

The lowest selected remaining percentage fills the innermost band; upper cells show watch
complications.

The three upper complication cells are customized in the **system watch-face editor**. Open
the watch's edit/customize action for WardPulse and select an upper cell to choose an available
complication provider. Exact controls and available providers vary with the watch's system.
These cells are separate from the usage rings selected in the phone's Watchface tab.

Choose usage rings on the phone. Watch weather and other system complications depend on
their own available data; refreshing provider usage does not itself update watch weather.
