# Read the Dashboard

Open **Dashboard** to see the reporting available from your connected providers. Related plan
and API connections appear together under their provider family: OpenAI, Anthropic or Cursor.
Each connection keeps its own data and status. Not every account provides spend, model detail,
purchased usage or a history chart.

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
to 0%; watch displays keep ordinary styling for that rounded value.

![Dashboard showing previous data and a Claude unsupported-response warning in the light theme.](/screenshots/phone-dashboard-light.png)

![Dashboard showing previous data and a Claude unsupported-response warning in the dark theme.](/screenshots/phone-dashboard-dark.png)

Read each plan's capacity **left** and the reporting status beside it. These captures show
a Claude unsupported-response warning and previous data.

Selected exhausted watch metrics remain present with an empty grey track and a pale-red zero
percentage. They do not disappear or get replaced by a less-used Claude window. The widget
also keeps exhausted rows as **0% left**. See [Watch](/guide/watch) and [Widget](/guide/widget).

## Spend, history and model detail

API reporting can show **Today**, **Week** and **Month** spend where available. A missing
spend report is not proof of zero billing. History and **Model usage** appear when the provider
supplies usable data; WardPulse does not create a local log of your prompts or a continuous
activity history.

Personal plan activity and API organization/team usage keep separate histories and balances
within a family. Use the source label when more than one connection is listed. Read each
chart's unit: cost, tokens or requests.

Some reporting services publish totals less frequently than WardPulse refreshes. A successful
refresh can therefore return unchanged figures. See [Sync](/guide/sync).

## Set budget limits and alert thresholds

These controls live on **Providers**, not Settings.

Find the connection you want to configure. Its **bell icon** opens **Alert thresholds**;
reporting connections also have a **piggy-bank icon** for **Budget limits**. A filled
piggy-bank or ringing bell indicates configured limits or rules, not successful provider sync.

![Providers action icons beside Organization reporting in the light theme.](/screenshots/phone-providers-light.png)

![Providers action icons beside Organization reporting in the dark theme.](/screenshots/phone-providers-dark.png)

**Piggy-bank icon:** Budget limits. **Bell icon:** Alert thresholds.

### Budget limits

1. On a reporting row, tap the **piggy-bank icon** to open **Budget limits**.
2. Enter limits for **Today**, **Week** or **Month** in the connection's reporting currency,
   for example **25.00**. Amounts must be at least **0.01**, with up to two decimal places.
3. Leave a period empty for no limit, then tap **Save**.

![Organization reporting Budget dialog with a Today 25.00 draft in the light theme.](/screenshots/phone-budget-limits-light.png)

![Organization reporting Budget dialog with a Today 25.00 draft in the dark theme.](/screenshots/phone-budget-limits-dark.png)

Unsaved example: **Today 25.00**, with **Week** and **Month** empty. **Cancel** discards the draft.

### Alert thresholds

1. Tap the connection's **bell icon** to open **Alert thresholds**.
2. For a plan connection, choose an **Alert when** value for **Plan** or **Purchased**.
   Reporting connections use the budget periods that have limits.
3. Choose **50**, **30**, **20**, **10** or **0% left**, or **Off** to disable the rule.
4. Tap **Save**.

For example, **Plan → 20% left** alerts when the reported plan capacity is 20% or less.
For a reporting connection with a **25.00** Today limit, a **20% left** Today threshold is
reached at **20.00** spent. These examples depend on usable reporting from that connection.

![Claude plan Alerts dialog with a Plan 20% left draft in the light theme.](/screenshots/phone-alert-thresholds-light.png)

![Claude plan Alerts dialog with a Plan 20% left draft in the dark theme.](/screenshots/phone-alert-thresholds-dark.png)

Unsaved example: **Plan 20% left**, **Purchased Off**. **Cancel** keeps the previous rules.

A budget threshold stays unavailable until that period has a limit. Each connection has its
own rules; another provider's spend does not count against that connection's limit.
**Cancel** leaves the existing settings unchanged.

Budget limits help you track spending. They do not stop requests, change the provider's
spending limits or alter billing. Active threshold alerts appear on Dashboard.
[Plan recovery notifications](/guide/sync#plan-recovery-notifications) are configured separately.

## Understand status and update time

The header shows **Updated …**. After a failed refresh that recovers earlier data, it can show
**Showing previous data · Updated …** and a sync issue. The earlier records keep their original
successful times. The header timestamp does not certify that every provider has fresh data:
one connection may refresh while another retains stale data.

Problem marks identify reporting or capacity issues. The top-bar count represents provider
families with problems. Tap it to reach the first affected Dashboard family, then read the
named connection or card. These status marks are separate from your alert rules, so
**No alerts** does not by itself mean every provider is healthy or freshly synced.
For rejected credentials, provider errors and rate limits, use [Troubleshooting](/guide/troubleshooting).
