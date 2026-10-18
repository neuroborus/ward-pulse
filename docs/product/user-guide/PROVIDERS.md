# Connect providers

Open **Providers** on the phone. Connect your existing plan account or a key that can read
organization/team reports. You do not choose or change a subscription tier in WardPulse.
Each connection is independent.

| Family | Plan connection | Reporting connection |
| --- | --- | --- |
| OpenAI | <span id="codex-subscription">[Codex plan](/guide/providers-openai#codex-plan)</span> | <span id="openai-platform-reporting">[Platform reporting](/guide/providers-openai#platform-reporting)</span> |
| Anthropic | <span id="claude-subscription">[Claude plan](/guide/providers-anthropic#claude-plan)</span> | <span id="anthropic-organization-reporting">[Organization reporting](/guide/providers-anthropic#organization-reporting)</span> |
| Cursor | <span id="cursor-plan">[Cursor plan](/guide/providers-cursor#cursor-plan)</span> | <span id="cursor-team-admin-api">[Team Admin API](/guide/providers-cursor#team-admin-api)</span> |

![Providers showing separate plan and reporting connections with their statuses in the light theme.](/screenshots/phone-providers-light.png)

![Providers showing separate plan and reporting connections with their statuses in the dark theme.](/screenshots/phone-providers-dark.png)

Plan and reporting connections have separate statuses. Connected rows do not confirm a
fresh Dashboard report.

Plan connections are experimental. Reporting connections need the provider's organization
or team reporting access. A personal plan login does not supply that access automatically.

## Cursor browser fallback

If Cursor's built-in sign-in fails, follow [Advanced paste](/guide/providers-cursor#advanced-paste).
Desktop cookie instructions are available for <span id="chrome">[Chrome](/guide/providers-cursor#chrome)</span>,
<span id="firefox">[Firefox](/guide/providers-cursor#firefox)</span> and <span id="safari">[Safari](/guide/providers-cursor#safari)</span>, followed
by <span id="save-the-token">[saving the token in WardPulse](/guide/providers-cursor#save-the-token)</span>.

## Check the connection

Saving a reporting key starts a check. Read the result beside the same connection:

| Status | What to do |
| --- | --- |
| **Checking…** | Wait for the report request to finish. |
| **Connected** | Reporting succeeded. Open Dashboard to read the available data. |
| **Not verified** | Reporting access for the saved key has not been confirmed. Refresh when available. |
| **Key rejected** | Check or replace the key in this reporting row. |
| **Access denied** | Check the key's reporting permissions and the account's access at the provider. |
| **Could not check** | Check the phone's connection and retry when available. |

A saved key alone does not mean Connected. A working plan login also does not confirm the
reporting key beside it. Connected can still show zero or no history before the provider
has usage to report. See [Troubleshooting](/guide/troubleshooting) for other messages.

## Reconnect, change or remove a connection

- For **Codex plan** or **Claude plan**, tap the connected row and choose **Reconnect** or
  **Disconnect**. For **Cursor plan**, choose **Sign in again** to replace the dashboard login.
- Cancelling a replacement sign-in keeps the existing connection.
- To replace a reporting key, tap its row, enter the new **Value** and tap **Save**. Check the
  result beside that row. The saved key is not displayed back into the field.
- To change only **Label**, edit **Label**, leave **Value** blank and tap **Save**.
  Label names this connection on your phone.
- **Remove** clears the selected pasted credential. **Cancel** leaves it unchanged.

Disconnecting or removing a connection clears its local credential and prevents obsolete
data from being reused. It does not revoke a key at the provider. Revoke it in that
provider's key settings if needed; other WardPulse connections remain independent.

## Budget limits and alert thresholds

The **bell icon** opens **Alert thresholds**. Reporting rows also have a **piggy-bank icon**
for **Budget limits**. These are WardPulse settings; they do not change your provider's plan
or billing limits. Follow the [Dashboard examples](/guide/dashboard#set-budget-limits-and-alert-thresholds).

## Keep credentials private

WardPulse stores credentials encrypted on this phone and uses them to authenticate requests
directly to their provider. Credentials are not sent to a WardPulse server or the watch.
Enter them only in the matching sign-in page or credential field, never in an issue or screenshot.

If you need help, [report an issue](/guide/report-an-issue) with the visible connection name
and message, without sharing the credential.
