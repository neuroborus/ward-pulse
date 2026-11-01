# Home widget

The WardPulse home widget shows selected remaining percentages, applicable purchased
credits and reported reset times. It is updated from the phone's reporting and has its
own metric choices.

## Add and configure it

1. Open your Android launcher's widget picker, often by pressing and holding an empty area of
   the home screen and choosing **Widgets**.
2. Add the **WardPulse** widget.
3. Open WardPulse on the phone and select the **Widget** tab.
4. Under **Widget metrics → Home screen widget**, select the available metrics you want.
5. Check **Next widget payload**. Connect a provider under **Providers** if there are no metrics yet.

![Widget selection showing checked metrics and five of six slots used in the light theme.](/screenshots/phone-widget-settings-light.png)

![Widget selection showing checked metrics and five of six slots used in the dark theme.](/screenshots/phone-widget-settings-dark.png)

This October 2026 selection example has five metrics selected under **Home screen widget**;
choices save as you tap.

You can select up to **six** metrics. Widget selection is independent of Watchface; changing
one does not change the other. Claude and Codex windows remain separate widget choices,
including Fable weekly when reported, and Cursor Models/Other Models can be separate rows.
The watch's three-band/two-pair limits do not apply to the widget's six independent rows.
Widget updates continue while saved watch choices need correction. Selected exhausted pools stay as
**0%**. With all six slots used, deselect a metric before adding another.

Lower remaining percentages appear first. The phone's metric selection is shared by
placed WardPulse widgets; each widget's size determines how much is visible.

## Resize for the information you need

Press and hold the placed widget to reveal your launcher's resize handles. Drag the side
handles to change width and the top or bottom handles to change height. The card fills
that allocation and centers its complete content, with space around fewer rows.

The widget keeps its own text size when the phone's font-size or bold-text setting changes.
Resize the widget to make room for more information.

### Width changes the columns

Each row represents **one metric**. Its columns show information about that metric,
rather than placing more metrics side by side.

| Available width | Columns shown |
| --- | --- |
| Narrow | Remaining percentage |
| Medium | Remaining percentage and full provider/metric label |
| Wide | Remaining percentage, label and applicable purchased balance/reset time |

Labels use two lines for the provider and full pool name, including **Cursor / Models**.
Purchased credits appear as a compact balance such as `32.4K`; `K` and `M` mean thousands
and millions. A reset appears only when that selected allowance reports a real reset time.
It uses your phone's local time, for example **Reset 10 Feb 11:45**. Missing reset times are
omitted, and a displayed boundary does not itself confirm that capacity has returned.

When width is tight, a reset may disappear before a purchased balance. Further narrowing
hides the complete right-hand details column, then labels. Percentages retain their size;
rows and columns are omitted whole rather than cut off. Increasing width adds information
columns, not more metric rows.

### Height changes the rows

The widget shows complete rows that fit, up to your six selected metrics. Shortening it
hides rows from the bottom without deselecting them. Increase its height to reveal more.
The number that fits depends on your launcher's allocation and the actual labels/values.

- **No metrics** means no selected metrics are available, including a deliberately empty
  selection. Check the Widget tab and provider data.
- **Resize widget** means metrics exist but no complete row fits. Increase the available
  width or height. Exceptionally tiny widgets may expose this state through accessibility
  without drawing text that would be cut off.
- **STALE** means earlier data is retained after a failed refresh. The badge needs space
  above the rows, so a stale widget may show fewer rows. Refresh the phone when
  network/provider access is available; see [Sync](/guide/sync#offline-failed-refresh-and-restart).

A missing value is not invented as zero. Accessibility retains each visible metric's full
identity even when its label is hidden, and describes purchased/reset details when displayed.

## Open the app from the widget

Tap the widget to open **Dashboard**, whether WardPulse is already running or opens from
closed. If an in-app edit form is open, the tap cancels the unfinished edit before opening
Dashboard. Save an edit first if you want to keep it. Use **Refresh** in the app when needed.

For an old widget, missing rows or delayed updates, use
[Troubleshooting](/guide/troubleshooting#widget-is-empty-clipped-or-old).

## Earlier launcher appearance

The following October 2026 images show the former widget renderer. They preserve earlier
examples of width and height changes; they do not show the current typography, reset line
or full-allocation card.

### Earlier wide widget

![October 2026 former widget with percentages, labels and purchased balances in the light theme.](/screenshots/phone-home-widget-light.png)

![October 2026 former widget with percentages, labels and purchased balances in the dark theme.](/screenshots/phone-home-widget-dark.png)

### Earlier labeled widget

![October 2026 former widget with percentages and provider/metric labels in the light theme.](/screenshots/phone-home-widget-with-label-light.png)

![October 2026 former widget with percentages and provider/metric labels in the dark theme.](/screenshots/phone-home-widget-with-label-dark.png)

### Earlier percentage-only widget

![October 2026 former widget with percentage-only rows in the light theme.](/screenshots/phone-home-widget-percent-only-light.png)

![October 2026 former widget with percentage-only rows in the dark theme.](/screenshots/phone-home-widget-percent-only-dark.png)

### Earlier short widget

![October 2026 former widget showing its first complete row in the light theme.](/screenshots/phone-home-widget-short-light.png)

![October 2026 former widget showing its first complete row in the dark theme.](/screenshots/phone-home-widget-short-dark.png)
