# Watch and watch face

The Wear app shows the phone's derived usage summary. The optional WardPulse face adds
remaining-capacity rings. The phone owns provider sign-in, budgets and alert rules.

## Set up the watch

1. Pair the watch with your phone using its manufacturer's normal setup. Check that its
   companion app reports it connected.
2. Install matching WardPulse phone and Wear builds supplied through the same distribution.
3. Connect a provider on the phone, then refresh **Dashboard**.
4. Open WardPulse from the watch's app launcher and allow the summary to arrive.

Until its first valid phone summary, Wear shows a setup prompt rather than inventing usage.
You do not enter keys or sign in to providers on the watch. If the phone has data but the watch
does not, follow [Troubleshooting](/guide/troubleshooting#watch-summary-is-missing-or-old).

## Read the Wear app

**Glance** shows remaining capacity with provider labels, compact tracks, optional purchased
credits and refresh status. Swipe upward to the second page, **Plan windows**, to see the
reported windows and when they return. Reset times may be unavailable.

Tap **Alerts: N** on Glance when N is greater than zero to open the active alert list.
**Alerts: 0** is disabled. If the list was already open when its last alert cleared, it shows
**No active alerts**. The count describes alerts, not whether every provider freshly synced.
Configure rules on the phone's **Providers** tab; Wear has no rule editor.

The refresh control sends a request to the phone. Cadence and rate-limit states can disable
it; **Stale** indicates recovery is needed. See [Sync and notifications](/guide/sync).
Wear can mark an otherwise received summary stale after two hours without a newer summary.

## Choose usage rings

1. On the phone, open **Watchface**.
2. Under **Ring slots → Wear & watch face**, select the known metrics you want.
3. Read the count of used slots. The limit is three bands; some supported Codex/Cursor pairs
   share a band, so the count can differ from the number of checked rows.
4. Deselect an existing band choice first only if your desired choice is disabled because all
   three bands are full. The other half of an already selected pair may remain available
   without using another band. Separately, an unavailable metric explains its missing percentage.
5. Check **Next watch payload**, then allow the updated summary to reach Wear.

Claude plan windows collapse to the tightest known window, including an exhausted zero. The
phone Dashboard still lists the individual windows. On Glance, a selected exhausted metric
remains a grey empty track with a pale-red **0%** token; it is not replaced by a less-used window. Tiny
positive values rounded to zero retain ordinary styling. Paired known pools retain their identity.

**Next watch payload** describes what the phone will send; it is not delivery confirmation.
Ring choices are independent of the phone's [home-widget selection](/guide/widget).

## Select and customize the face

The WardPulse face is a separate installed package. It uses Watch Face Format version 2 and
requires **Wear OS 5 or later**. The Wear app and face have different compatibility requirements.
Use the watch's normal face picker to select WardPulse after installing its compatible build.

The three upper complication cells are customized in the **system watch-face editor**. Open
the watch's edit/customize action for WardPulse and select an upper cell to choose an available
complication provider. Exact controls and available providers vary with the watch's system.
These cells are separate from the usage rings selected in the phone's Watchface tab.

You do not need to manually select WardPulse's internal ring/split data sources. Watch weather
and other system complications depend on their own available data. Provider refresh on the
phone does not itself obtain watch weather readings.

## Source notes

Phone sources are under `apps/phone_flutter/lib/`: `watchface_screen.dart`
(`WatchfaceScreen`) in `watchface`, and `watch_ring_preferences.dart`
(`watchRingSlotCount`, `watchRingSlotCost`, `collapseClaudePlanRing`) in `settings`.
Wear sources are in the `app.wardpulse.wear` package: `ui/WardPulseApp.kt`
(`WardPulseApp`, `EmptyDashboardScreen`, `HomePage`), `ui/GlanceLegend.kt`
(`GlanceLegendPage`), `ui/GlanceModels.kt` (`glanceRefreshChrome`), and
`model/WatchDashboardSummary.kt` (`WatchDashboardSummary.isStaleAt`). See face reference
[layer rules](/product/watch-ring-design#layer-rules) and
[upper cells](/product/watch-ring-design#upper-cells-revision-2026-10-09), Wear reference
[composition](/product/wear-glance-design#composition) and
[refresh control](/product/wear-glance-design#refresh-status-control).
In the watch-face package `apps/watchface_wff/`, format version is declared in the
main `AndroidManifest.xml` (`com.google.wear.watchface.format.version`);
[Android's version table](https://developer.android.com/training/wearables/wff#versioning-wff)
defines Wear OS 5 as the minimum for version 2.
