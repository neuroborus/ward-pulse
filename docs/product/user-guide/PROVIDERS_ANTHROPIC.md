# Anthropic

Connect **Claude plan** to read the plan windows and monthly extra usage available from
your Claude account. Connect **Organization reporting** separately for Console API expenses.

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

Use a key with reporting access to the intended Console organization. A Claude chat
subscription or Claude plan login does not grant this access. Console API expenses are
separate from Claude Plan's monthly Extra usage Credits; neither supplies the other's data.
See Claude's explanation of [how subscription and API billing differ](https://support.claude.com/en/articles/9876003-i-have-a-paid-claude-subscription-pro-max-team-or-enterprise-plans-why-is-claude-api-usage-billed-separately-from-my-paid-claude-plan).

WardPulse uses one **ordinary organization-scoped API key** with actual reporting rights
for the linked account. Leave workspace scope unset. WardPulse rejects Console **Admin**
keys, including values starting with `sk-ant-admin`; replace one in this same reporting row.
A key without that marker still needs organization eligibility and account rights. This
reporting field is separate from Claude plan's authorization-code field.

### Convert an individual organization

Individual Console API organizations do not have Admin API access. The Console flow
observed in October 2026 was **Settings → Organization → Convert to team organization →
Convert to team**, followed by organization details and API-use questions. Review the
current Console prompts and your organization's eligibility before changing it. Selecting
**organization scope** for a key does not convert the organization. Conversion is separate
from buying a claude.ai Team chat plan; availability, terms and reversal are not guaranteed.

### Connect the key

1. Select the intended organization in Claude Console and open **API keys → Create key**.
2. Choose a name and expiry using the controls Console offers.
3. Set **Linked account** to **yourself** and leave workspace scope unset. The linked
   account must have the organization's reporting rights; a subscription plan does not grant them.
4. Create the key and copy its value when shown. It is shown only once.
5. Open **Providers → Anthropic → Organization reporting** in WardPulse.
6. Paste the complete key in **Value** and optionally add a phone-local **Label**.
7. Tap **Save** and read that row's check result. **Checking…** means a report request is
   running; **Connected** requires a successful live check for the current saved key.

A Console Admin value is rejected locally before a report request. For a saved Admin
key, **Key rejected** explains that you need an ordinary organization-scoped replacement.
Open the row, enter it in **Value** and **Save**. Policy rejection keeps the previous key,
label and cached report; it does not verify access or erase previous data.
Other **Key rejected** results call for checking or replacing the key. For **Access denied**,
review both the organization's reporting access and the key's rights/scope. A connected Claude
plan cannot verify the reporting key. Do not share keys in issues or screenshots.

### Read Console expenses

Dashboard shows this source's **Today**, **Week** and **Month** spend independently of
its optional local caps. Today starts at midnight UTC, Week on Monday UTC, and Month on
the first calendar day UTC. These periods are not your Claude Plan window or billing cycle.
**As of** is the source's successful report time, displayed in your phone's local timezone;
retained **Stale** data keeps that earlier time and those earlier amounts.

Known Money is displayed to whole cents. **USD 0.00** can be a reported zero or a tiny
positive amount rounded to zero cents; it is not proof of no charges. **No spend reported**
means a complete amount was not established. Console costs arrive in daily buckets: missing the current day's cost
bucket can leave a period unavailable even when older days or request history are present.
A successful request or empty usage history does not establish no charges for all time.
Refreshing WardPulse cannot make the provider publish missing buckets sooner.

**Budget limits** are local advisory caps, not provider spending controls. Setting no cap
still shows known spend on Dashboard and makes it selectable on Widget. Widget keeps the
reported amount and currency, with **No cap**, **Cap unavailable** or **Percentage unavailable**
when applicable; missing spend stays **Unavailable**. Watchface budget rings still require
known spend, a positive same-currency cap and a usable percentage. Saved unavailable
choices remain removable. Widget Extra usage details keep independent monthly used/cap
Credits, distinct from purchased credits left. See [Dashboard](/guide/dashboard#spend-history-and-model-detail),
[Watch](/guide/watch#choose-usage-rings) and [Widget](/guide/widget#add-and-configure-it).

## Reconnect, change or remove a connection

If your Claude plan sign-in expires, open **Providers → Anthropic → Claude plan** and
sign in again. If it is still shown as connected, use **Reconnect**. An Organization
reporting key cannot renew a Claude plan sign-in.

Use **Reconnect** or **Disconnect** for Claude plan. For Organization reporting, replace
**Value** and tap **Save**, change only **Label** with Value blank, or **Remove** the saved
key. **Cancel** discards the unsaved edit. Blank Value preserves the saved key; the field
never displays it back. Removing it in WardPulse does not revoke it at the provider. See
[connection management](/guide/providers#reconnect-change-or-remove-a-connection).
