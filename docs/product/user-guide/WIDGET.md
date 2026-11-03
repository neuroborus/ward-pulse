# Home widget

The WardPulse home widget shows selected allowances, reported expenses, applicable purchased
credits and real reset times. It is updated from the phone's reporting and has its
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

**Claude Extra usage** can be selected when Claude reports a usable percentage. A missing
monthly cap does not disable an otherwise usable percentage. When its percentage is
unavailable, the choice remains unavailable; a saved choice can still be removed. Missing
amounts or caps are not filled in as zero or Unlimited. Its right-hand details show used
and cap amounts independently in the reported units, such as Credits. These describe usage,
not purchased credits left; a monthly reset is not estimated.

Console and Cursor Team expenses can be selected with known spend even without a local
cap. Known zero is valid; missing spend is unavailable. Saved unavailable choices can still
be removed. With a usable same-currency cap and reported percentage, the row shows percent
left and actual spent/cap details. Without a cap it shows the amount and **No cap**. A present
unusable cap shows **Cap unavailable**; a usable cap without a percentage shows
**Percentage unavailable**. Amounts keep their reported currency and cents. Missing spend
shows a dash and **Unavailable**, rather than an invented number.

**Next widget payload** distinguishes an empty choice, no available default metrics and
saved choices without current results. It describes the configured/current payload; your
launcher's size determines which complete rows and details are visible. Budget periods use
UTC Today, Monday Week and calendar Month, with no inferred reset. Local caps do not stop
provider spending.

Lower remaining percentages appear first. The phone's metric selection is shared by
placed WardPulse widgets; each widget's size determines how much is visible.

## Resize for the information you need

Press and hold the placed widget to reveal your launcher's resize handles. Drag the side
handles to change width and the top or bottom handles to change height. A compact card
is centered within that allocation, leaving unused exterior space transparent. The whole
allocation remains tappable; transparent space does not give launcher cells back.

The widget keeps its own text size when the phone's font-size or bold-text setting changes.
Resize the widget to make room for more information.

### Width changes the columns

Each row represents **one metric**. Its columns show information about that metric,
rather than placing more metrics side by side.

| Available width | Columns shown |
| --- | --- |
| Narrow | Complete percentage or self-contained expense amount |
| Medium | Primary value and full provider/metric label |
| Wide | Primary value, label and applicable expense, Extra or purchased/reset details |

Labels use two lines for the provider and full pool name, including **Cursor / Models**.
Purchased credits appear as a compact balance such as `32.4K`; `K` and `M` mean thousands
and millions. A reset appears only when that selected allowance reports a real reset time.
It uses your phone's local time, for example **Reset 10 Feb 11:45**. Missing reset times are
omitted, and a displayed boundary does not itself confirm that capacity has returned.

When width is tight, a reset may disappear before a purchased balance. Further narrowing
hides the complete right-hand details column, then labels. Expense amounts retain their
currency and sign, using a smaller size only when the normal size cannot fit
after columns are hidden. Rows and columns are omitted whole rather than cut off. Increasing width adds information
columns, not more metric rows.

### Height changes the rows

The widget shows complete rows that fit, up to your six selected metrics. Shortening it
hides rows from the bottom without deselecting them. Increase its height to reveal more.
The number that fits depends on your launcher's allocation and the actual labels/values.

- **No metrics** means there are no current rows to show, including a deliberately empty
  selection or unavailable allowance choices. A saved expense with missing spend can still
  appear as an **Unavailable** row. Check the Widget tab and provider data.
- **Resize widget** means metrics exist but no complete row fits. Increase the available
  width or height. Exceptionally tiny widgets may expose this state through accessibility
  without drawing text that would be cut off.
- **STALE** means earlier data is retained after a failed refresh. The badge needs space
  in the same header as the mark, without reserving another row. Refresh the phone when
  network/provider access is available; see [Sync](/guide/sync#offline-failed-refresh-and-restart).

A missing value is not invented as zero. Accessibility retains each visible metric's full
identity even when its label is hidden, and describes only displayed details and resets.
Expense spend, Extra used/cap and purchased credits left have distinct meanings.

## Open the app from the widget

Tap the widget to open **Dashboard**, whether WardPulse is already running or opens from
closed. If an in-app edit form is open, the tap cancels the unfinished edit before opening
Dashboard. Save an edit first if you want to keep it. Use **Refresh** in the app when needed.

For an old widget, missing rows or delayed updates, use
[Troubleshooting](/guide/troubleshooting#widget-is-empty-clipped-or-old).

## Earlier launcher appearance

The following October 2026 images show the former widget renderer. They preserve earlier
examples of width and height changes; they do not show the current typography, reset line
or intrinsic card with transparent unused exterior.

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
