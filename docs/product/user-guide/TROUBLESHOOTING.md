# Troubleshooting

Start with the phone: check **Dashboard** status and update time, then the matching row under
**Providers**. A saved connection and a successful fresh report are different states.

## No provider data yet

If Dashboard says **Connect a provider**, use **Open Providers** and connect the appropriate
plan account or organization/team reporting key. [Connect providers](/guide/providers) explains
the prerequisites for each row.

A **Connected** reporting row can show zero or no history before there is activity to report.
This alone does not require replacing the key. See [Cursor's reporting history](/guide/providers-cursor#read-the-history)
for its update timing.

If a connection is saved but a meter says **Unknown**, **Balance unavailable** or is absent,
check what that account exposes in the provider's own dashboard. Some providers do not report
every balance, reset time, model breakdown or history. A missing value is not a zero.

## Loading or an error screen

The first load can briefly show a spinner. For a failed load, use the displayed **Retry** action
after checking the phone's network access. **Providers** remains the place to check credentials.
If loading or errors continue, note the visible status and the step that failed when
[reporting the issue](#asking-for-help).

## Credential rejected or access unavailable

Read the connection name on Dashboard or **Providers**. **Platform reporting**,
**Organization reporting** and **Team Admin API** are separate from the plan login
in the same provider family.

- **Key rejected:** check that you entered the full key for the named reporting row, or
  replace it there. Use **Edit key** where offered.
- **Access denied:** review the key's reporting permissions and the account's access at
  the provider, then refresh. The value can belong to a valid key without permission to
  read these reports.
- **Could not check:** check the phone's network access and retry when available. A
  timeout or unavailable service does not prove that the key is wrong.
- **Could not read saved key:** WardPulse could not read the key from this phone. Retry;
  if the problem persists, re-enter the key in the named reporting row.
- **Could not read reporting data:** refresh later. If the problem persists,
  [report the issue](#asking-for-help) with the visible message, without sharing the key.

For **Rate limited**, follow [Previous data, offline or rate limited](#previous-data-offline-or-rate-limited).

Check the setup for the named connection:

- [OpenAI Platform reporting](/guide/providers-openai#platform-reporting) needs an organization
  Admin key, not an ordinary project key.
- [Anthropic Organization reporting](/guide/providers-anthropic#organization-reporting) needs
  organization reporting access; personal/service keys must not be workspace-scoped.
  An Individual API organization needs the [Console conversion](/guide/providers-anthropic#convert-an-individual-organization).
- [Cursor Team Admin API](/guide/providers-cursor#team-admin-api) needs a Team key with reporting
  access; check [General → View team resources](/guide/providers-cursor#team-key-permissions).

For a plan/session error, use the named plan row's **Reconnect** or Cursor's
**Sign in again**. Claude callback paste expects **CODE#STATE**, not a reporting key.
Do not paste a secret into an unrelated row or a help request.

## Previous data, offline or rate limited

**Showing previous data** and **STALE** identify earlier data kept after failed refresh. Restore
network access and refresh on the phone. Earlier successful values and their timestamps can
survive restart, but a connection with no successful report has no data to recover.

![Dashboard showing previous data and a Claude unsupported-response warning in the light theme.](/screenshots/phone-dashboard-light.png)

![Dashboard showing previous data and a Claude unsupported-response warning in the dark theme.](/screenshots/phone-dashboard-dark.png)

These captures show **Claude returned an unsupported usage response.** with **Showing previous
data**. Earlier data remains visible; the message alone does not establish why the response
was unsupported.

If a provider reports a rate limit, wait for any supplied availability/reset time or try later.
Repeated refresh taps cannot remove a provider limit. A successful report may still contain
unchanged values, especially for reporting such as Cursor Team Admin API.
See [Sync](/guide/sync) for cadence and stored data.

## Watch summary is missing or old

1. Check that the phone Dashboard has the data you expect, then refresh it.
2. Confirm the watch is connected in its normal companion app and that matching WardPulse phone
   and Wear builds are installed.
3. Open the Wear app and allow delivery. Watch refresh requests still depend on the phone.
4. Check the phone's **Watchface** selection and **Next watch payload** if usage rings are missing.

Wear also marks summaries stale after two hours without a newer summary. A phone summary preview
does not confirm receipt on the watch. If the face's upper cells need adjustment, use the system
watch-face editor; those cells are not the phone's ring picker. See [Watch](/guide/watch).
Do not clear credentials or reset pairing as the first response to a delayed summary.

## Widget is empty, clipped or old

- Check **Widget** metric choices and whether those metrics have known provider data. **No metrics**
  can be a valid empty selection.
- If you see **Resize widget**, increase its height. For missing labels/credits, increase width;
  smaller sizes deliberately show fewer complete columns or rows.
- Open and refresh WardPulse on the phone. A **STALE** widget can keep earlier rows after a
  failed report; the background interval is approximate and Android may delay it.

Widget choices are separate from Watchface. See [Home widget](/guide/widget).

## Plan recovery notifications do not appear

Check **Settings → Notifications → Plan recovery** and Android's notification permission for
WardPulse. This feature is for an exhausted plan becoming usable again; it does not send every
Dashboard threshold alert as a notification. It needs a later report to detect recovery, so
its delivery is not an exact reset alarm.

## Asking for help

Use the [issue format](/guide/report-an-issue), then [open a GitHub issue](https://github.com/neuroborus/ward-pulse/issues/new).
Sign in to GitHub if prompted. Describe **Actual behaviour**, **Expected behaviour** and
**Steps to reproduce**; **Notes** is optional.

Useful notes include the WardPulse version, phone/watch OS, affected provider row, visible
status and update time. If sharing a screenshot, hide account labels and private usage
figures as well as credentials.

Never share an API key, dashboard cookie, authorization code, account identifier, prompt or
full provider response. Do not send sensitive logs. The visible status and the steps you tried
are enough to begin a help request.
