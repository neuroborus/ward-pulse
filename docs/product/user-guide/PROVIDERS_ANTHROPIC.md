# Anthropic

Connect **Claude plan** for your plan windows. Connect **Organization reporting** separately
for Claude Console API usage and costs.

## Claude plan

Use the Claude account whose plan windows you want to read.

1. Open **Providers → Anthropic → Claude plan**.
2. In **Connect Claude plan**, tap **Open browser**, sign in and approve the requested access.
3. Copy the authorization code from the callback page, including its **CODE#STATE** form.
4. Return to WardPulse, paste it into the authorization field and tap **Continue**.

This field expects the callback authorization code, not an API key. If the attempt expires
or is cancelled, start a new attempt rather than reusing the old code.

When Claude reports an included **Fable weekly** window, WardPulse shows it separately
from your other plan windows. It is a sub-cap of the same weekly allowance, not additional
weekly usage. Its percentage describes the Fable sub-cap itself. Missing usage stays
unknown, and a reset is shown only when Claude supplies a valid reset for that window.
An absent Fable window does not create an allowance or change your other windows.

## Organization reporting

Use a Claude Console key with permission to read organization usage and costs. An
organization-scoped personal key uses your linked account's permissions. An existing
eligible service-account key can also be used if it is not workspace-scoped. An existing
Console Admin API key is another option. See Anthropic's [Usage and Cost API guide](https://platform.claude.com/docs/en/manage-claude/usage-cost-api).

Individual API organizations do not have Admin API access. If Console shows **Individual
API plan**, convert the existing organization before checking this connection again.
Setting a key's scope to Organization alone does not convert the organization.

### Convert an individual organization

The steps below reflect the Console flow observed on October 17, 2026. If your page
differs, confirm the conversion options with Anthropic before continuing.

1. In Claude Console, open [**Settings → Organization**](https://platform.claude.com/settings/organization).
2. Find **Convert to team organization** and choose **Convert to team**.
3. Complete the organization details and API-use questions shown in the form, then confirm
   the conversion.
4. Return to WardPulse and check **Organization reporting** again if you already saved an
   organization-scoped key.

This changes the Console organization. It is separate from buying a
[Claude Team chat plan](https://support.claude.com/en/articles/9876003-i-have-a-paid-claude-subscription-pro-max-team-or-enterprise-plans-why-is-claude-api-usage-billed-separately-from-my-paid-claude-plan).

### Create a reporting key

These steps create your own personal key. If you already have a suitable reporting
key, skip to [Connect the key](#connect-the-key). Console Admin keys are separate from
personal keys and do not have a **Scope** selector.

1. Open Claude Console [**API keys**](https://platform.claude.com/settings/keys) for the
   organization you want to monitor.
2. Create a key named **WardPulse**. Set **Linked account** to yourself and choose
   **Scope: Organization**, rather than a workspace. Your linked account must have
   permission to read organization usage and costs.
3. Copy the resulting key and keep it private.

A Claude Enterprise Analytics key is for a different service; it is not the credential
for this row.

### Connect the key

1. Open **Providers → Anthropic → Organization reporting** in WardPulse.
2. Paste the key into **Value**, optionally add a **Label**, and tap **Save**.
3. Wait for the check beside that row. **Connected** means a report succeeded.

![Saved Anthropic Organization reporting-key editor with empty Value and Label fields in the light theme.](/screenshots/phone-reporting-key-light.png)

![Saved Anthropic Organization reporting-key editor with empty Value and Label fields in the dark theme.](/screenshots/phone-reporting-key-dark.png)

This saved-key editor keeps the existing key when **Value** is left blank; **Remove** clears
that credential. The empty field's **API key** text is a placeholder.

![Providers showing the Organization reporting connection and its status in the light theme.](/screenshots/phone-providers-light.png)

![Providers showing the Organization reporting connection and its status in the dark theme.](/screenshots/phone-providers-dark.png)

Read Organization reporting's own status, separately from Claude plan.

For **Access denied**, confirm that the key belongs to the intended Console organization,
has organization reporting rights and is not workspace-scoped. A working Claude plan login
does not confirm the reporting key. Zero or missing history can be normal before API usage
is reported. API token history can appear before reported costs. Costs stay unknown until
Anthropic reports them.

### Read reported costs and budget limits

Organization reporting covers the organization authorized by the key, separately from your
Claude plan. **Today** starts at midnight UTC, **Week** starts on Monday UTC, and **Month**
starts on the first day of the calendar month UTC.

Costs and budget percentages reflect what Anthropic has reported to date. They do not
guarantee that all recent charges have been published. A period stays unavailable if any
required day's costs are missing, even when token history is visible. A reported zero is
different from missing costs; a period with no elapsed time is unavailable.

Set advisory ceilings with the **piggy-bank icon's Budget limits** beside
**Organization reporting** in **Providers**.
These limits are local to WardPulse and do not stop API usage or change Anthropic's spending
limits. A percentage needs reported spend and a positive ceiling in the same currency.
Unavailable budget choices stay visible but cannot be added until usable data and a ceiling
are available. Existing selections can still be removed, and unavailable reports do not
reset saved ceilings.

## Reconnect, change or remove a connection

Use **Reconnect** or **Disconnect** for Claude plan. Reporting-key controls are separate;
see [connection management](/guide/providers#reconnect-change-or-remove-a-connection).
