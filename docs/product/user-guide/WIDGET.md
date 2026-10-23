# Home widget

The WardPulse home widget shows selected remaining percentages and applicable purchased
credits. It is updated from the phone's reporting and has its own metric choices.

## Add and configure it

1. Open your Android launcher's widget picker, often by pressing and holding an empty area of
   the home screen and choosing **Widgets**.
2. Add the **WardPulse** widget.
3. Open WardPulse on the phone and select the **Widget** tab.
4. Under **Widget metrics → Home screen widget**, select the available metrics you want.
5. Check **Next widget payload**. Connect a provider under **Providers** if there are no metrics yet.

![Widget selection showing checked metrics and five of six slots used in the light theme.](/screenshots/phone-widget-settings-light.png)

![Widget selection showing checked metrics and five of six slots used in the dark theme.](/screenshots/phone-widget-settings-dark.png)

This example has five metrics selected under **Home screen widget**; choices save as you tap.

You can select up to **six** metrics. Widget selection is independent of Watchface; changing
one does not change the other. Claude windows remain separate widget choices, and Cursor
Models/Other Models can be separate rows. Selected exhausted pools stay as **0% left**.
With all six slots used, deselect a metric before adding another.

The displayed ordering puts lower remaining percentages first. The phone's metric selection is
shared by placed WardPulse widgets; each widget's size determines how much of it is visible.

## Resize for the information you need

Press and hold the placed widget to reveal your launcher's resize handles. Drag the side
handles to change width and the top or bottom handles to change height.

### Width changes the columns

Each row represents **one metric**. Its columns show information about that metric, rather
than placing more metrics side by side.

| Available width | Columns shown |
| --- | --- |
| Narrow | Remaining percentage |
| Medium | Remaining percentage and provider/metric label |
| Wide | Remaining percentage, provider/metric label and applicable purchased credits |

At a narrow width, the same five selected metrics show only their percentages:

![Narrow WardPulse widget showing five percentage-only rows in the light theme.](/screenshots/phone-home-widget-percent-only-light.png)

![Narrow WardPulse widget showing five percentage-only rows in the dark theme.](/screenshots/phone-home-widget-percent-only-dark.png)

Widen it to show which provider and metric each row belongs to:

![Medium-width WardPulse widget showing percentages and provider/metric labels in the light theme.](/screenshots/phone-home-widget-with-label-light.png)

![Medium-width WardPulse widget showing percentages and provider/metric labels in the dark theme.](/screenshots/phone-home-widget-with-label-dark.png)

With more width, purchased credits appear beside the applicable plan row. In this example,
only the Codex row has a purchased-credit balance to show:

![Wide WardPulse widget showing five metric rows and Codex purchased credits in the light theme.](/screenshots/phone-home-widget-light.png)

![Wide WardPulse widget showing five metric rows and Codex purchased credits in the dark theme.](/screenshots/phone-home-widget-dark.png)

Shrinking the width hides credits first, then labels; percentages remain. Increasing width
adds information columns, not more metric rows. Launcher behaviour and text size affect fit.

### Height changes the rows

The widget shows only complete rows that fit, up to your six selected metrics. Shortening it
hides rows from the bottom of the ordered list without deselecting them. Increase its height
to reveal more rows, or reduce unused height with the resize handles.

The short widget below has the same five metrics selected, but only its first row fits:

![Short wide WardPulse widget showing only the first row, Cursor Other Models, in the light theme.](/screenshots/phone-home-widget-short-light.png)

![Short wide WardPulse widget showing only the first row, Cursor Other Models, in the dark theme.](/screenshots/phone-home-widget-short-dark.png)

- **No metrics** means no selected metrics are available, including a deliberately empty
  selection. Check the Widget tab and provider data.
- **Resize widget** means metrics exist but no complete row fits. Increase the widget's height.
- **STALE** means earlier data is being retained after a failed refresh. Refresh the phone
  when network/provider access is available; see [Sync](/guide/sync#offline-failed-refresh-and-restart).

A missing value is not invented as zero to fill a row.

## Open the app from the widget

Tap the widget to open **Dashboard**, whether WardPulse is already running or opens from
closed. If an in-app edit form is open, the tap cancels the unfinished edit before opening
Dashboard. Save an edit first if you want to keep it. Use **Refresh** in the app when needed.

For an old widget, missing rows or delayed updates, use
[Troubleshooting](/guide/troubleshooting#widget-is-empty-clipped-or-old).
