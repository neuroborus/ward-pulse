# Anthropic

Use **Organization reporting** to see your Claude Console organization's API expenses and
usage. **Claude plan** is temporarily unavailable in the public app.

## Claude plan

WardPulse has paused Claude plan sign-in and monitoring in the public app because
Anthropic's policy restricts third-party apps from using Claude plan credentials.
Tap the grey **Connect** button under **Providers → Anthropic → Claude plan** to read
the explanation. [Anthropic's authentication policy](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)

The pause also applies to previously connected plans. WardPulse removes the saved sign-in
on this phone and keeps your saved watch and widget choices. Check your subscription's usage,
including any 5-hour, weekly, Fable and Extra usage figures your plan provides, in
[Claude → Settings → Usage](https://claude.ai/settings/usage).

## Organization reporting

Use a key with reporting access to the intended Console organization. This connection
covers the organization's API expenses and usage. Your Claude subscription limits and
Extra usage appear in your Claude account's Usage settings.
[How Claude bills subscription and API usage](https://support.claude.com/en/articles/9876003-i-have-a-paid-claude-subscription-pro-max-team-or-enterprise-plans-why-is-claude-api-usage-billed-separately-from-my-paid-claude-plan)

WardPulse uses one **ordinary organization-scoped API key** with actual reporting rights
for the linked account. Leave workspace scope unset. WardPulse rejects Console **Admin**
keys, including values starting with `sk-ant-admin`; replace one in this same reporting row.
A key without that marker still needs organization eligibility and account rights.

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
review both the organization's reporting access and the key's rights and scope. Do not
share keys in issues or screenshots.

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
choices remain removable. See [Dashboard](/guide/dashboard#spend-history-and-model-detail),
[Watch](/guide/watch#choose-usage-rings) and [Widget](/guide/widget#add-and-configure-it).

## Reconnect, change or remove a connection

For Organization reporting, replace **Value** and tap **Save**, change only **Label** with
Value blank, or **Remove** the saved key. **Cancel** discards the unsaved edit.
Blank Value preserves the saved key; the field
never displays it back. Removing it in WardPulse does not revoke it at the provider. See
[connection management](/guide/providers#reconnect-change-or-remove-a-connection).
