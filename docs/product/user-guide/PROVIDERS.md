# Connect providers

Open **Providers** on the phone. Each provider family has separate plan and reporting rows.
Choose the row for the data you want; connecting one does not automatically connect the other.

| Family | Plan row | Reporting row |
| --- | --- | --- |
| OpenAI | Codex subscription | Platform reporting |
| Anthropic | Claude subscription | Organization reporting |
| Cursor | Cursor plan | Team Admin API |

Plan connections are experimental. Reporting rows need administrative credentials. Keep
tokens, keys and authorization codes private, and enter them only into the matching
provider's sign-in page or WardPulse's credential field.

## Codex subscription

Use the OpenAI account whose Codex plan you want to read.

1. Tap **Codex subscription**.
2. In **Connect Codex**, note the displayed one-time code. **Copy code** copies it.
3. Tap **Open browser** and follow the OpenAI sign-in page. Enter the displayed code there.
4. Return to WardPulse and allow the sign-in attempt to finish.

If the attempt expires or fails, cancel it and start again with a new code. Do not paste an
OpenAI Platform API key into this flow. Reporting through Platform does not provide your
personal Codex subscription limits.

## Claude subscription

Use the Claude account whose plan windows you want to read.

1. Tap **Claude subscription**.
2. In **Connect Claude**, tap **Open browser**, sign in and approve the requested access.
3. Copy the authorization code from the callback page, including its **CODE#STATE** form.
4. Return to WardPulse, paste it into the authorization field and tap **Continue**.

This field expects the callback authorization code, not a reporting API key. If the code has
expired or the attempt was cancelled, start a new attempt rather than reusing the old callback.

## Cursor plan

1. Tap **Cursor plan**. If it is already **Connected**, choose **Sign in again** in the account
   dialog to open a replacement dashboard sign-in.
2. Sign in to the Cursor account you want to connect and follow the provider's prompts.
3. After sign-in completes, return to WardPulse and check Dashboard reporting.

If you already have a dashboard session in a desktop browser, tap the **About Cursor sign-in**
help icon, then **Advanced paste**. The paste dialog includes cookie instructions.

1. In desktop Chrome or Edge, open **cursor.com/dashboard** and sign in to the same account.
2. Right-click the page and choose **Inspect**.
3. Open **Application → Storage → Cookies** and select the Cursor site.
4. Find **WorkosCursorSessionToken**. The **Filter** box can find it by name.
5. Copy only **Value**, not the cookie name or the complete Cookie header.
6. Paste that value in **Cursor plan · Paste token** and tap **Save**.

If it is missing, confirm you are signed in, reload the dashboard and check the selected site
under Cookies. To use app sign-in instead, tap **Cancel**, then the **Cursor plan** row; if it
is already **Connected**, choose **Sign in again**.
The cookie is a private session credential; WardPulse stores it encrypted on the phone.
The browser steps follow the official [Chrome](https://developer.chrome.com/docs/devtools/application/cookies)
and [Edge](https://learn.microsoft.com/en-us/microsoft-edge/devtools/storage/cookies) documentation.

## OpenAI Platform reporting

Use an organization **Admin API key** that can read organization usage and cost reporting.
An ordinary project API key is not sufficient. OpenAI's
[administration overview](https://developers.openai.com/api/reference/administration/overview)
links to Admin API key creation.

1. Obtain the organization's Admin API key through its authorized administrator.
2. In WardPulse, tap **Platform reporting** under OpenAI.
3. Paste the key into **Value**. Optionally add a **Label** to identify this reporting connection.
4. Tap **Save** and check the Dashboard's reporting status.

This row reads API organization reporting, not personal ChatGPT or Codex subscription usage.

## Anthropic Organization reporting

Use a Claude Console organization with Usage & Cost Admin API access and an organization
Admin API key. This is separate from your Claude subscription sign-in. Anthropic documents
the account and credential requirements in its
[Usage and Cost API guide](https://platform.claude.com/docs/en/manage-claude/usage-cost-api).

1. Obtain the organization's Admin API key through its authorized administrator.
2. Tap **Organization reporting** under Anthropic.
3. Paste it into **Value**, optionally add a **Label**, and tap **Save**.
4. Check reporting status on Dashboard.

This connection targets Claude Platform organization reporting. A Claude Enterprise Analytics
key belongs to a different service and is not the credential for this row.

## Cursor Team Admin API

You need an **Enterprise team administrator** and the team's Admin API key. A paid Teams plan
alone does not grant access. Cursor lists the availability in its
[API overview](https://cursor.com/docs/api), with details in the
[Admin API documentation](https://cursor.com/docs/account/teams/admin-api).

1. Have the Enterprise team administrator create the team's API key in the Cursor dashboard.
2. Tap **Team Admin API** under Cursor.
3. Paste the key into **Value**, optionally add a **Label**, and tap **Save**.
4. Check Dashboard reporting. Usage may lag by about an hour even after a successful refresh.

That freshness note applies to the Team Admin API, not the experimental Cursor plan row.

## Reconnect, change or remove a connection

- For connected **Codex subscription** or **Claude subscription**, tap the row and choose
  **Reconnect** or **Disconnect**. For **Cursor plan**, the replacement action is **Sign in again**.
- Cancelling a replacement sign-in preserves an existing valid connection.
- To change a reporting key or its label, tap its row. The stored key is not displayed back
  into **Value**. Leave Value blank to keep the key when updating its optional label.
- To remove a pasted credential, use **Remove**. Cursor's Advanced paste dialog also offers
  Remove when a token is saved. **Cancel** leaves the current connection unchanged.

Disconnect/removal clears the selected local credential and prevents obsolete stored data
from being reused. It does not revoke an API key at the provider; use that provider's key
management to revoke it when needed. Other connections are independent.

For **Alert thresholds** and **Budget limits**, use the action icons on the connection row.
They configure how WardPulse tracks your usage; see [Dashboard](/guide/dashboard). A saved
connection can still be rejected or temporarily unavailable: [Troubleshooting](/guide/troubleshooting)
explains the next steps without sharing secrets.
