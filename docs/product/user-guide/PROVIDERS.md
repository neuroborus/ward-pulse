# Connect providers

Open **Providers** on the phone. Each provider family has separate plan and reporting rows.
Connect an existing account or organization/team Admin API key to read its usage. You do not
choose or change a subscription tier in WardPulse. Connecting one row does not automatically
connect the other.

| Family | Plan row | Reporting row |
| --- | --- | --- |
| OpenAI | Codex subscription | Platform reporting |
| Anthropic | Claude subscription | Organization reporting |
| Cursor | Cursor plan | Team Admin API |

Plan connections are experimental. Reporting rows need administrative credentials. Keep
tokens, keys and authorization codes private, and enter them only into the matching
provider's sign-in page or WardPulse's credential field.

![Providers showing separate plan and reporting rows in the light theme.](/screenshots/phone-providers-light.png)

![Providers showing separate plan and reporting rows in the dark theme.](/screenshots/phone-providers-dark.png)

Plan logins and organization/team reporting have separate connection rows.

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

![Cursor sign-in help with the Advanced paste action in the light theme.](/screenshots/phone-cursor-sign-in-help-light.png)

![Cursor sign-in help with the Advanced paste action in the dark theme.](/screenshots/phone-cursor-sign-in-help-dark.png)

**Advanced paste** opens the session-cookie instructions.

Open **cursor.com/dashboard** in your desktop browser and sign in to the same Cursor account.
Find **WorkosCursorSessionToken** using the instructions for your browser below. Copy only
its **Value**, without the cookie name, a `name=` prefix or the complete Cookie header.

### Chrome

1. Right-click the dashboard and choose **Inspect**.
2. Open [**Application → Storage → Cookies**](https://developer.chrome.com/docs/devtools/application/cookies)
   and select the **cursor.com** site.
3. Filter for **WorkosCursorSessionToken**, select it and copy **Value** from its preview.

### Firefox

1. Open **Browser Tools → Web Developer Tools**.
2. Select [**Storage**](https://firefox-source-docs.mozilla.org/devtools-user/storage_inspector/),
   then **Cookies** and the **cursor.com** domain.
3. Find **WorkosCursorSessionToken** in the table and copy its **Value**.

### Safari

1. In [**Safari → Settings → Advanced**](https://support.apple.com/en-ca/guide/safari/sfri20948/mac),
   enable **Show features for web developers** if needed.
2. Open [**Develop → Show Web Inspector**](https://webkit.org/web-inspector/enabling-web-inspector/).
3. Select **Storage**, then the Cursor domain under **Cookies**.
4. Find **WorkosCursorSessionToken**. Double-click its **Value** cell, select and copy the
   **Value** field without editing it. Copying the whole cookie can include its name and
   other fields.

### Save the token

Paste the copied value into **Cursor plan · Paste token** and tap **Save**.

![Cursor paste dialog with instructions and an empty saved-token Value field in the light theme.](/screenshots/phone-cursor-paste-token-light.png)

![Cursor paste dialog with instructions and an empty saved-token Value field in the dark theme.](/screenshots/phone-cursor-paste-token-dark.png)

Shown with a saved token: leave **Value** blank to keep it, or paste a replacement and tap **Save**.

If it is missing, confirm you are signed in, reload the dashboard and check the selected site
under Cookies. To use app sign-in instead, tap **Cancel**, then the **Cursor plan** row; if it
is already **Connected**, choose **Sign in again**.
The cookie is a private session credential; WardPulse stores it encrypted on the phone.

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

![Anthropic Organization reporting with empty Value and Label fields in the light theme.](/screenshots/phone-reporting-key-light.png)

![Anthropic Organization reporting with empty Value and Label fields in the dark theme.](/screenshots/phone-reporting-key-dark.png)

Enter the organization's Admin API key in **Value**. **Label** is optional.

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

The **bell icon** opens **Alert thresholds**. Reporting rows also have a **piggy-bank icon**
for **Budget limits**. They configure how WardPulse tracks your usage; see
[Dashboard examples](/guide/dashboard#set-budget-limits-and-alert-thresholds). A saved
connection can still be rejected or temporarily unavailable: [Troubleshooting](/guide/troubleshooting)
explains the next steps without sharing secrets.
