# Read the Dashboard

Open **Dashboard** to see the reporting available from your connected providers. Related plan
and API connections appear together under their provider family: OpenAI, Anthropic or Cursor.
Each connection keeps its own data and status. Not every account provides spend, model detail,
purchased usage or a history chart.

## Display order

Provider families with the most urgent status appear first: **Error**, **Auth required**,
**Rate limited**, **Warning**, **Stale**, **Unknown**, then **OK**. Each family takes the
most urgent status of its connections and allowances.

When statuses match, higher monthly spend comes first where the currencies can be compared.
Remaining ties use **Anthropic → Cursor → OpenAI**. Ordinary changes to percentages or spend
keep the current order; a status change or an added or removed provider family recalculates it.

Within each family, the plan appears before API reporting, and each history stays beside
its source. Allowance cards, **Usage history** and **Model usage** name their source in their
own headings, such as **Codex plan** or **OpenAI · Platform reporting**. Repeated sources
also carry **Source N** labels to keep their data distinct while scrolling.
Remaining percentages do not set the Dashboard order. The
[watch orders selected metrics by remaining capacity](/guide/watch#display-order).

## Read balances and bars

- **Plan** percentages speak in capacity **left**. A fuller plan bar means more remaining
  capacity. For example, 20% left means 80% has been used.
- **Cursor Models** uses a blue plan fill; **Other Models** uses teal. These colors identify
  the plan pools. The provider header identifies the family; status marks show each pool's
  state.
- **Purchased** allowance bars track the amount **used**. Their headline can show a remaining
  balance, **Unlimited**, a percent used, or **Balance unavailable**, depending on the report.
- **Claude Extra usage** shows the reported monthly amount used and applicable cap in
  **Credits**, independently when available. It is a usage meter, not a prepaid balance.
  A missing used amount is not zero; a missing or zero cap is neither **Unlimited** nor
  proof of exhaustion. Its percentage is shown only when reported.
- Read the units beside credits or purchased balances. A credit count is not a dollar amount.
- A plan window can include a reset time. **Reset time unavailable** means WardPulse does not
  have that time; it does not mean the window never resets.

**Unknown** and **Balance unavailable** mean a value was not established. A real known
**0% left** means the reported capacity is exhausted. A small positive percentage may round
to 0%; watch displays keep ordinary styling for that rounded value.

Selected exhausted watch metrics remain present with an empty grey track and a pale-red zero
percentage. They do not disappear or get replaced by a less-used Claude window. The widget
also keeps exhausted rows as **0% left**. See [Watch](/guide/watch) and [Widget](/guide/widget).

## Spend, history and model detail

API reporting can show **Today**, **Week** and **Month** spend where available. A missing
spend report is not proof of zero billing. Each reporting source's compact expense card
shows known spend,
including zero, with **Local cap** shown separately. **Not set** does not hide known spend
or itself mean an unhealthy source. A cap does not enforce provider billing. **As of** is
that source's successful report time in local time; **Stale** retains its previous values
and time, independently of the Dashboard's latest update. Today starts at midnight UTC,
Week on Monday UTC, and Month on the first calendar day UTC.

Each source has aligned Today/Week/Month rows, or equal-width columns on a wide screen,
with one source status and **As of** time. Read the source named inside each expense card.
Known Money rounds to whole cents, so a tiny positive amount may display as **USD 0.00**.
Partial history bars do not establish a complete total: a missing daily cost bucket can leave a period unavailable.
History and **Model usage** appear when the provider
supplies usable data; WardPulse does not create a local log of your prompts or a continuous
activity history.

Claude Plan extra usage provides monthly used/cap figures rather than Console API costs
or Today/Week spending. It does not create a daily cost history. Ordinary Claude plan
windows remain separate.

Personal plan activity and API organization/team usage keep separate histories and balances
within a family. Use the source label when more than one connection is listed. Read each
chart's unit: cost, tokens or requests. Known bars can remain visible when **No totals**
means the provider did not supply a complete total.

Some reporting services publish totals less frequently than WardPulse refreshes. A successful
refresh can therefore return unchanged figures. See [Sync](/guide/sync).

## Set budget limits and alert thresholds

These controls live on **Providers**, not Settings.

Find the connection you want to configure. Its **bell icon** opens **Alert thresholds**;
reporting connections also have a **piggy-bank icon** for **Budget limits**. A filled
piggy-bank or ringing bell indicates configured limits or rules, not successful provider sync.

**Piggy-bank icon:** Budget limits. **Bell icon:** Alert thresholds.

Budget and Alerts titles identify the provider and connection, even when
reporting rows have the same saved **Label**. Check that title before editing.

### Budget limits

1. On a supported reporting row, such as **OpenAI → Platform reporting**, tap the
   **piggy-bank icon** to open **Budget limits**.
2. Enter limits for **Today**, **Week** or **Month** in the connection's reporting currency,
   for example **25.00**. Amounts must be at least **0.01**, with up to two decimal places.
3. Leave a period empty for no limit, then tap **Save**.

**Cancel** discards an unsaved budget draft. Claude Extra usage's reported cap is not a
WardPulse-editable monetary budget.

### Alert thresholds

1. Tap the connection's **bell icon** to open **Alert thresholds**.
2. For a plan connection, set **Plan**, an individual reported **Plan window**, or **Purchased**.
   Reporting connections use **Today**, **Week** and **Month** where a budget limit is set.
3. Choose **100**, **50**, **30**, **20**, **10** or **0% left**. To enter another whole
   number from **0 to 100**, choose **Custom % left** and fill in **% left**.
4. Tap **Save**, or **Cancel** to keep the previous rules.

**Plan** is the default for windows without their own rule. For an individual window,
**Use Plan default** follows that default, **Off** disables its alert, and a percentage
sets a separate threshold. Changing Plan keeps those individual choices.

Reported windows are listed even when they are not selected for the watch. When Cursor
reports **Cursor Models** and **Other Models**, they have separate Plan-window controls;
**Purchased** controls its on-demand allowance. Before a report arrives, you can still
prepare Plan and Purchased rules.

For example, **20% left** alerts when the reported remaining capacity is **20% or less**.
A custom **17% left** uses the same rule. Both **0% left** and **100% left** are enabled
thresholds; choose **Off** to disable one. Custom input must be a whole number in range;
correct invalid fields before saving, or explicitly choose **Off**. Windows also offer
**Use Plan default**.

A saved window rule is kept if the window temporarily disappears from reporting. You can
inspect it as an unavailable window or select **Use Plan default** to remove its override.
If that same window returns, its saved choice is used again, including after a label change.
An alert needs a reported percentage; a rule does not invent missing usage.

For a reporting connection with a **25.00** Today limit, a **20% left** Today threshold is
reached at **20.00** spent. Each period has its own rule. A period without a budget limit
stays unavailable and keeps any previously saved threshold.

![Cursor plan Alerts with Other Models set to Custom % left and 17 in the % left field, in the light theme.](/screenshots/phone-alert-thresholds-light.png)

![Cursor plan Alerts with Other Models set to Custom % left and 17 in the % left field, in the dark theme.](/screenshots/phone-alert-thresholds-dark.png)

Unsaved example: **Plan 20% left**, **Cursor Models → Use Plan default**,
**Other Models → Custom % left** with **17** in **% left**, and **Purchased Off**.
Scroll within the dialog to see all controls. **Cancel** keeps the previous rules.

When current data is available, saving a rule updates alerts from that data without waiting
for another provider report. It does not make the provider's usage statistics update sooner.
Each connection has its own rules; another provider's spend does not count against its limit.

Budget limits help you track spending. They do not stop requests, change the provider's
spending limits or alter billing. Active threshold alerts appear on Dashboard.
[Plan recovery notifications](/guide/sync#plan-recovery-notifications) are configured separately.

## Saved rejection warnings

If a saved connection is rejected, Dashboard keeps a warning naming that connection.
It describes a past rejection, so it can remain after the connection works again.
Claude and Fable share one Claude plan warning.

Tap the warning text to open **Providers** at the named connection. Review its current
status and use its own sign-in or key controls if recovery is still needed. Opening the
warning does not dismiss it. Tap its **X** to dismiss just that warning without leaving
Dashboard.

Refresh, switching tabs, restarting the app, reconnecting and **Disconnect** or **Remove**
keep the warning until X. Repeated failures of that same saved connection do not bring a
dismissed warning back. A newly saved or reconnected connection can produce another warning
if it is later rejected. Android **Clear storage** removes all local records, including
these warnings. Existing disconnections without a recorded rejection do not create a warning.

These warnings do not change current connection statuses, problem counts, allowance values
or update times. Permission, network, service and reporting-data errors remain separate.

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
