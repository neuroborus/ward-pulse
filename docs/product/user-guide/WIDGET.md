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

Select metrics under **Home screen widget**; choices save as you tap.

You can select up to **six** metrics. Widget selection is independent of Watchface; changing
one does not change the other. Claude windows remain separate widget choices, and Cursor
Models/Other Models can be separate rows. Selected exhausted pools stay as **0% left**.
With all six slots used, deselect a metric before adding another.

The displayed ordering puts lower remaining percentages first. The phone's metric selection is
shared by placed WardPulse widgets; each widget's available size can fit a different number
of rows and columns.

![STALE WardPulse home widget showing four complete rows on the Android launcher in the light theme.](/screenshots/phone-home-widget-light.png)

![STALE WardPulse home widget showing four complete rows on the Android launcher in the dark theme.](/screenshots/phone-home-widget-dark.png)

This STALE example shows four complete rows at its current size, while five metrics are selected.

## Resize for the information you need

Use the launcher's resize handles. The widget shows complete rows that fit, which can be fewer
than your six selected metrics. As width shrinks, purchased credits and labels can disappear
while percentages remain. A tall unused area can be reduced with the resize handles.

- **No metrics** means no selected metrics are available, including a deliberately empty
  selection. Check the Widget tab and provider data.
- **Resize widget** means metrics exist but no complete row fits. Increase the widget's height.
- **STALE** means earlier data is being retained after a failed refresh. Refresh the phone
  when network/provider access is available; see [Sync](/guide/sync#offline-failed-refresh-and-restart).

Launcher behaviour and text size affect fit. A narrow widget can show fewer labels and credits
than a wide one. A missing value is not invented as zero to fill a row.

## Open the app from the widget

Tap the widget to open **Dashboard**, whether WardPulse is already running or opens from
closed. If an in-app edit form is open, the tap cancels the unfinished edit before opening
Dashboard. Save an edit first if you want to keep it. Use **Refresh** in the app when needed.

For an old widget, missing rows or delayed updates, use
[Troubleshooting](/guide/troubleshooting#widget-is-empty-clipped-or-old).
