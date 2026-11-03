# Anthropic

Connect **Claude plan** to read the plan windows and monthly extra usage available from
your Claude account.

## Claude plan

Use the Claude account whose plan windows you want to read.

1. Open **Providers → Anthropic → Claude plan**.
2. In **Connect Claude plan**, tap **Open browser**, sign in and approve the requested access.
3. Copy the authorization code from the callback page, including its **CODE#STATE** form.
4. Return to WardPulse, paste it into the authorization field and tap **Continue**.

This field expects the callback authorization code, not an API key. If the attempt expires
or is cancelled, start a new attempt rather than reusing the old code.

**Extra usage** shows the monthly amount Claude reports as used and the applicable monthly
cap, when available. WardPulse displays these quantities in **Credits**. Do not read that
credit count as a dollar amount or a prepaid balance. This monthly meter does not provide
Today or Week spending or an estimated reset date.

Availability depends on your Claude account, its settings and the data Claude reports.
Connecting WardPulse does not enable extra usage or change your billing. For a managed
account, your organization may control access and applicable limits. See Claude's
[personal-plan credit guide](https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans)
or [Team and legacy seat-based Enterprise credit guide](https://support.claude.com/en/articles/12005970-manage-usage-credits-for-team-and-seat-based-enterprise-plans)
for those accounts' controls.

WardPulse shows the usable figures your account reports without filtering by plan name.
This does not mean every account has extra usage enabled or provides the same figures.
A missing, disabled or incomplete meter is not zero spending. A missing or zero cap is not
**Unlimited** or proof of exhaustion; any known used amount or cap is shown independently.
Its percentage appears only when reported.

Plan windows are independent of extra usage. Only the windows Claude reports appear;
a missing 5-hour window does not make other windows or extra usage unavailable. Reset
times appear only when Claude reports them for that window.

When Claude reports an included **Fable weekly** window, WardPulse shows it separately
from your other plan windows. It is a sub-cap of the same weekly allowance, not additional
weekly usage. Its percentage describes the Fable sub-cap itself. Missing usage stays
unknown, and a reset is shown only when Claude supplies a valid reset for that window.
An absent Fable window does not create an allowance or change your other windows.

## Organization reporting

Claude Console API reporting is planned separately. It is not included in the Claude Plan
extra-usage meter. You do not need a Console reporting key to connect Claude plan.
See Claude's explanation of [how subscription and API billing differ](https://support.claude.com/en/articles/9876003-i-have-a-paid-claude-subscription-pro-max-team-or-enterprise-plans-why-is-claude-api-usage-billed-separately-from-my-paid-claude-plan).

### Convert an individual organization

WardPulse's Console organization-conversion setup instructions are retired while this
integration is deferred.

### Connect the key

The Console reporting-key connection is deferred. Use Claude plan sign-in for the monthly
Extra usage figures described above.

## Reconnect, change or remove a connection

Use **Reconnect** or **Disconnect** for Claude plan. See
[connection management](/guide/providers#reconnect-change-or-remove-a-connection).
