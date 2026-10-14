# Read the Dashboard

Open **Dashboard** to see the reporting available from your connected providers. Sections can
change with the data a provider exposes: not every account has spend, model detail, purchased
usage or a history chart.

## Read balances and bars

- **Plan** percentages speak in capacity **left**. A fuller plan bar means more remaining
  capacity. For example, 20% left means 80% has been used.
- **Purchased** allowance bars track the amount **used**. Their headline can show a remaining
  balance, **Unlimited**, a percent used, or **Balance unavailable**, depending on the report.
- Read the units beside credits or purchased balances. A credit count is not a dollar amount.
- A plan window can include a reset time. **Reset time unavailable** means WardPulse does not
  have that time; it does not mean the window never resets.

**Unknown** and **Balance unavailable** mean a value was not established. A real known
**0% left** means the reported capacity is exhausted. A small positive percentage may round
to 0%; watch displays retain ordinary styling for that rounded value rather than treating it
as a truly exhausted window.

Selected exhausted watch metrics remain present with an empty grey track and a pale-red zero
percentage. They do not disappear or get replaced by a less-used Claude window. The widget
also keeps exhausted rows as **0% left**. See [Watch](/guide/watch) and [Widget](/guide/widget).

## Spend, history and model detail

Platform reporting can show **Today**, **Week** and **Month** spend. A missing spend report is
not proof of zero billing. History and **Model usage** appear when the provider supplies usable
data; WardPulse does not create a local log of your prompts or a continuous activity history.

Some reporting services publish aggregates less frequently than WardPulse refreshes. A
successful refresh can therefore return unchanged figures. See [Sync](/guide/sync).

## Set budget limits and alert thresholds

These controls live on **Providers**, not Settings.

1. Open **Providers** and find the connection to configure.
2. For a reporting connection, tap **Budget limits** and enter limits for the periods you want:
   **Today**, **Week**, **Month**. Use the connection's reporting currency, for example **25.00**.
   Amounts must be at least **0.01**, with up to two decimal places. Leave a period empty for
   no limit; tap **Save**.
3. Tap **Alert thresholds**. For plan connections, choose an **Alert when** value for **Plan**
   or **Purchased**. Reporting connections use the configured budget periods.
4. Choose a **% left** threshold, or **Off** to disable that rule, then tap **Save**.

A budget threshold stays unavailable until that period has a limit. Each connection has its
own rules; another provider's spend does not count against that connection's limit.
**Cancel** leaves the existing settings unchanged.

Budget limits are your local reporting ceilings. They do not stop API requests, change the
provider's spending limits or alter billing. Active threshold alerts appear on Dashboard.
Interruption notifications are the separate [Plan recovery feature](/guide/sync#plan-recovery-notifications).

## Understand status and update time

The header shows **Updated …**. After a failed refresh that recovers earlier data, it can show
**Showing previous data · Updated …** and a sync issue. The recovered records keep their
original successful times. The header timestamp does not certify that every provider has
fresh data: one connection may refresh while another retains stale data.

Problem marks identify reporting or capacity issues. The top-bar problem control can take you
to the relevant Dashboard section. These status marks are separate from your opt-in alert
rules, so **No alerts** does not by itself mean every provider is healthy or freshly synced.
For rejected credentials, provider errors and rate limits, use [Troubleshooting](/guide/troubleshooting).

## Source notes

Phone sources are under `apps/phone_flutter/lib/`. Display, in `dashboard`:
`dashboard_screen.dart` (`AllowanceSummaryCard`, `BudgetSummaryCard`, `_SyncHeader`,
`_ProviderDashboardSectionView`, `_ModelUsagePanel`); `dashboard_models.dart`
(`AllowanceState`, `DashboardSnapshot`). Rules, in `providers` and `settings`:
`alert_threshold_dialogs.dart` (`ConnectionAlertsDialog`, `ConnectionBudgetDialog`);
`alert_percent_threshold_editor.dart` (`AlertPercentThresholdEditor`). App navigation:
`ward_pulse_app.dart` (`_revealProblem`). See the dashboard reference
[balances](/product/phone-dashboard-design#balances) and
[status rules](/product/phone-dashboard-design#rules), and privacy policy
[cached phone data](/product/privacy-policy#data-stored-on-the-phone).
