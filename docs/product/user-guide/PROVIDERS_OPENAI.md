# OpenAI

Connect **Codex plan** for personal plan limits and token activity. Connect **Platform
reporting** separately for API organization usage and costs.

## Codex plan

Use the OpenAI account whose Codex plan you want to read.

1. Open **Providers → OpenAI → Codex plan**.
2. In **Connect Codex plan**, note the one-time code. **Copy code** copies it.
3. Tap **Open browser** and sign in to OpenAI. Enter the displayed code on that page.
4. Return to WardPulse and allow the sign-in attempt to finish.

If the attempt expires or fails, cancel it and start again with a new code. This sign-in
expects the account authorization, not an OpenAI Platform API key.

## Platform reporting

Use an organization [**Admin API key**](https://developers.openai.com/api/reference/administration/overview)
with access to [usage and cost reports](https://developers.openai.com/cookbook/examples/completions_usage_api).
An ordinary project API key is not sufficient.
This connection does not provide personal ChatGPT or Codex plan limits.

### Create a reporting key

1. Open OpenAI's [organization Admin API keys](https://platform.openai.com/settings/organization/admin-keys)
   for the organization you want to monitor.
2. Create an Admin API key named **WardPulse** and copy the resulting key.
3. If you cannot access this page or create the key, ask that organization's administrator
   to provide the reporting access.

### Connect the key

1. In WardPulse, open **Providers → OpenAI → Platform reporting**.
2. Paste the key into **Value**. Optionally add a **Label** to identify this connection.
3. Tap **Save** and wait for the check beside **Platform reporting**.
4. When it says **Connected**, open Dashboard to read the available reports.

![Saved OpenAI Platform reporting-key editor with empty Value and Label fields in the light theme.](/screenshots/phone-openai-reporting-key-light.png)

![Saved OpenAI Platform reporting-key editor with empty Value and Label fields in the dark theme.](/screenshots/phone-openai-reporting-key-dark.png)

This saved-key editor keeps the existing key when **Value** is left blank; **Remove** clears
it. The empty field shows a fixed `sk-admin-…` credential-type hint, not a revealed key.

For **Key rejected**, check that you pasted the full Admin key into this row. For
**Access denied**, review its reporting access and the organization it belongs to.
A successful connection can have zero or no history when there is no reported usage.

## Reconnect, change or remove a connection

Use **Reconnect** or **Disconnect** for Codex plan. For a reporting key, use its Value,
Label and Remove controls. See [connection management](/guide/providers#reconnect-change-or-remove-a-connection)
for keeping a saved key or cancelling a replacement.
