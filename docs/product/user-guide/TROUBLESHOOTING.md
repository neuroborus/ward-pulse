# Troubleshooting

Start with the phone: check **Dashboard** status and update time, then the matching row under
**Providers**. A saved connection and a successful fresh report are different states.

## No provider data yet

If Dashboard says **Connect a provider**, use **Open Providers** and connect the appropriate
plan account or organization/team reporting key. [Connect providers](/guide/providers) explains
the prerequisites for each row.

If a connection is saved but a meter says **Unknown**, **Balance unavailable** or is absent,
check what that account exposes in the provider's own dashboard. Some providers do not report
every balance, reset time, model breakdown or history. A missing capability is not a zero.

## Loading or an error screen

The first load can briefly show a spinner. For a failed load, use the displayed **Retry** action
after checking the phone's network access. **Providers** remains the place to check credentials.
If loading or errors continue, note the visible status and the step that failed for the maintainer.

## Credential rejected or access unavailable

1. Check the row you used. Subscription sign-in, organization Admin API keys and Cursor dashboard
   cookies are different credential types.
2. Confirm the correct provider account or organization and the required administrative access.
3. For a subscription/session error, use **Reconnect** or Cursor's **Sign in again**. For a reporting
   key, enter the replacement under that reporting row and **Save**.

OpenAI reporting requires an organization Admin key, not a project key. Cursor Team Admin API
requires Enterprise administrative access. Claude callback paste expects **CODE#STATE**, not a
reporting key. Do not paste a secret into an unrelated row or a help request.

## Previous data, offline or rate limited

**Showing previous data** and **STALE** identify retained data after failed refresh. Restore
network access and refresh on the phone. Earlier successful values and their timestamps can
survive restart, but a connection with no successful report has no data to recover.

If a provider reports a rate limit, wait for any supplied availability/reset time or try later.
Repeated refresh taps cannot remove a provider limit. A successful report may still contain
unchanged values, especially for aggregated reporting such as Cursor Team Admin API.
See [Sync](/guide/sync) for cadence and cache behaviour.

## Watch summary is missing or old

1. Check that the phone Dashboard has the data you expect, then refresh it.
2. Confirm the watch is connected in its normal companion app and that matching WardPulse phone
   and Wear builds are installed.
3. Open the Wear app and allow delivery. Watch refresh requests still depend on the phone.
4. Check the phone's **Watchface** selection and **Next watch payload** if usage rings are missing.

Wear also marks summaries stale after two hours without a newer summary. A phone summary preview
is not receipt confirmation. If the face's upper cells need adjustment, use the system watch-face
editor; those cells are not the phone's ring picker. See [Watch](/guide/watch).
Do not clear credentials or reset pairing as the first response to a delayed summary.

## Widget is empty, clipped or old

- Check **Widget** metric choices and whether those metrics have known provider data. **No metrics**
  can be a valid empty selection.
- If you see **Resize widget**, increase its height. For missing labels/credits, increase width;
  smaller sizes deliberately show fewer complete columns or rows.
- Open and refresh WardPulse on the phone. A **STALE** widget can retain earlier rows after a
  failed report; the background interval is approximate and Android may delay it.

Widget choices are separate from Watchface. See [Home widget](/guide/widget).

## Plan recovery notifications do not appear

Check **Settings → Notifications → Plan recovery** and Android's notification permission for
WardPulse. This feature is for an exhausted plan becoming usable again; it does not send every
Dashboard threshold alert as a notification. It needs a later report to detect recovery, so
its delivery is not an exact reset alarm.

## Asking for help

Useful information includes the WardPulse build/version, phone/watch OS, affected provider row,
visible status and update time, whether the phone has fresh data, and the steps you tried.
If sharing a screenshot, hide account labels and private usage figures as well as credentials.

Never share an API key, dashboard cookie, authorization code, account identifier, prompt or raw
provider payload. Do not send unreviewed sensitive logs. WardPulse has no diagnostic-export
button in the current normal Settings screen; visible status information is enough to begin.

## Source notes

Phone sources are under `apps/phone_flutter/lib/`. First-use/error UI, in `app` and
`dashboard`: `ward_pulse_app.dart` (`_LoadingView`, `_ErrorView`) and
`dashboard_screen.dart` (`ConnectProviderPrompt`, `_SyncHeader`). Settings, in
`settings`: `settings_screen.dart` (`SettingsScreen`, `_setRecoveryNotifications`).
Connection types, in `providers`: `provider_connection.dart` (`providerConnectionCatalog`).
Wear age: `WatchDashboardSummary.kt` (`WatchDashboardSummary.isStaleAt`) in the Wear
app's `app.wardpulse.wear` model package. Widget fit: `PhoneWidgetLayout.java`
(`PhoneWidgetLayout`) in the phone Android host's `app.wardpulse` Java source tree.
See provider reference [connection grouping](/product/provider-notes#connection-grouping),
privacy policy [phone recovery](/product/privacy-policy#data-stored-on-the-phone), and
security reference [logging rules](/product/security-model#logging-rules).
