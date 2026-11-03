# Cursor

Connect **Cursor plan** to read your personal dashboard plan. Connect **Team Admin API**
separately to read a team's usage and spend. A personal User API key does not replace the
Team API key required by that reporting connection.

## Cursor plan

1. Open **Providers → Cursor → Cursor plan**.
2. Sign in to the Cursor account you want to connect and follow the provider's prompts.
3. WardPulse closes sign-in only after capturing a session. Check Dashboard for a fresh report;
   saving a connection does not confirm that reporting succeeded.

If the row is already Connected, tap it and choose **Sign in again** to replace the login.
Cancelling the replacement preserves the existing connection.

When Cursor reports **Cursor Models** and **Other Models**, each is a separate included Plan
window. Configure them independently through the connection's bell icon; **Purchased**
controls on-demand usage. See [Alert thresholds](/guide/dashboard#alert-thresholds).

Google authorization is blocked in WardPulse's built-in browser because Google's
[secure-browser policy](https://developers.google.com/identity/protocols/oauth2/policies#use-secure-browsers)
does not allow embedded browsers for this flow. Use email for the **same Cursor account**
when offered, or **Cancel**, reopen **Cursor plan** and choose another offered method.
This does not require another account, a plan change or account unification.

For startup, page or session-reading problems, use **Retry**, **Cancel** or **Help**.
Retry clears the in-app session and starts over. After two minutes, automatic session checks
pause: continue password/MFA entry, then tap **Check again**. Waiting does not mean your
password was rejected. A failed or cancelled replacement keeps the saved connection.
For [Advanced paste](#advanced-paste), Cancel to Providers and open the plan row's help icon.
Signing in in another browser or returning to WardPulse does not transfer that browser's session.

This is an experimental dashboard-session connection. The reviewed official documentation does
not establish an equivalent authorization grant for these personal plan meters. SDK User API
keys and agent usage are separate from this connection and from Team reporting.

### Advanced paste

Use this when sign-in through WardPulse's built-in browser does not work. Tap the
**About Cursor plan sign-in** help icon, then **Advanced paste**.

![Cursor plan sign-in Help with the Advanced paste action in the light theme.](/screenshots/phone-cursor-sign-in-help-light.png)

![Cursor plan sign-in Help with the Advanced paste action in the dark theme.](/screenshots/phone-cursor-sign-in-help-dark.png)

Open **cursor.com/dashboard** in your desktop browser and sign in to the same Cursor
account. Find the **WorkosCursorSessionToken** cookie using the instructions below.
Copy only its **Value**, without the cookie name, a `name=` prefix or a full Cookie header.

### Chrome

1. Right-click the dashboard and choose **Inspect**.
2. Open [**Application → Storage → Cookies**](https://developer.chrome.com/docs/devtools/application/cookies)
   and select **cursor.com**.
3. Find **WorkosCursorSessionToken**, select it and copy its **Value** from the preview.

### Firefox

1. Open **Browser Tools → Web Developer Tools**.
2. Select [**Storage**](https://firefox-source-docs.mozilla.org/devtools-user/storage_inspector/),
   then **Cookies** and **cursor.com**.
3. Find **WorkosCursorSessionToken** and copy its **Value**.

### Safari

1. In [**Safari → Settings → Advanced**](https://support.apple.com/en-ca/guide/safari/sfri20948/mac),
   enable **Show features for web developers** if needed.
2. Open [**Develop → Show Web Inspector**](https://webkit.org/web-inspector/enabling-web-inspector/).
3. Select **Storage**, then the Cursor domain under **Cookies**.
4. Find **WorkosCursorSessionToken**. Double-click its **Value** cell and copy the Value
   without editing it. Copying the whole cookie can include other fields.

### Save the token

Paste the value into **Cursor plan · Paste token** and tap **Save**. The cookie is a private
session credential.

![Saved Cursor plan token editor with an empty Value field in the light theme.](/screenshots/phone-cursor-paste-token-light.png)

![Saved Cursor plan token editor with an empty Value field in the dark theme.](/screenshots/phone-cursor-paste-token-dark.png)

This saved-token editor keeps the existing token when **Value** is left blank; **Remove**
clears it. The saved value is not displayed.

If the cookie is missing, confirm that you are signed in, reload the dashboard and check
the selected site under Cookies. To return to app sign-in, tap **Cancel**, then the Cursor
plan row; choose **Sign in again** if it is already Connected.

## Team Admin API

Use a **Team API key** with reporting access for the intended team. A User API key from a
personal plan's **API & SSH Keys** is a different credential. The personal plan alone does
not grant team reporting access.

If you already administer a team, go to [Create a Team key](#create-a-team-key).

### Before Unify

Creating a team may ask you to unify accounts. Before confirming, check the exact Cursor,
Grok and optional X accounts shown. [Completed unification cannot be undone](https://docs.x.ai/x-subscription/unify-accounts).
Support cannot reverse a completed unification.
Moving a [legacy Cursor plan such as Pro+ to The X Subscription](https://cursor.com/docs/account/pricing/legacy-cursor-plans)
is also permanent; the old plan terms cannot be restored.

Use a separate account if you want to leave your current account and legacy plan unchanged.
Check the plan and payment details before confirming a purchase or change.

### Create a team

1. Open <span id="create-team">**Get Teams**</span> on the [official pricing page](https://x.ai/pricing) and sign in to the
   account that will own the team.
2. Follow the team-creation steps and enter the team name. If you already paid for Premium
   but **Start a team** keeps returning you to Unify, open the
   [Premium team-creation entry](https://grok.com/dashboard/members?modal=create-team&tier=premium)
   in that account's browser session.
3. In the team's **Members** page, check your role and seat separately. **Admin** is a role;
   **Premium** is a seat. A team can have one person who holds both.
4. If you already purchased an unused Premium seat, assign that available seat through
   **Members → Seat**. Adding or upgrading seats can be billed; review the displayed cost
   before confirming a change.

An active personal Premium subscription by itself does not confirm that a team exists.
Team reporting availability depends on the team's access; do not buy or change a plan
solely on the assumption that any Team subscription includes these reports.
See [team roles, seats and invitations](https://docs.x.ai/x-subscription/team-plans).

### Create a Team key

Use the following verified reporting setup when the permission menu includes
<span id="team-key-permissions">**General → View team resources**</span>. Options and reporting access can differ by team.
If the option is unavailable, confirm your team's reporting access with the provider
instead of enabling **All permissions**.

1. Open the intended team's [**Team API keys**](https://grok.com/dashboard/api-keys/team).
2. Start a new key and enter **WardPulse** as its name.
3. Clear the preselected permissions, then enable only **General → View team resources**.
   Its description includes reading members, usage, spend, analytics, audit logs and settings.
4. Leave all other permissions off for this setup, including Agents/Models and write access.
5. Create the key and copy its value. Keep it private.

### Connect the key

1. Open **Providers → Cursor → Team Admin API** in WardPulse.
2. Paste the Team key into **Value**, optionally add a **Label**, and tap **Save**.
3. Wait for the result beside **Team Admin API**. **Connected** means reporting succeeded.

Read the status beside Team Admin API; Cursor plan is a separate connection.

For **Access denied**, check the Team key's reporting permissions and the team's
reporting access. If you use the setup above, confirm **General → View team resources**
is selected. For **Key rejected**, confirm that this is the intended team's complete
Team key, not a personal User key. See [connection status](/guide/providers#check-the-connection).

### Read the history

Team Admin API history counts requests, not tokens. These are raw usage events, not billed
request units. If no team activity is reported, **Usage history** may be absent.

**Today**, **Week** and **Month** spend show the authorized team's extra-paid usage, including
applicable Cursor fees. Included usage does not contribute to these amounts, even when it
appears in request history. Today starts at midnight UTC, Week on Monday UTC, and Month on
the first day of the calendar month UTC; these are not billing-cycle totals or personal-plan
percentages.

**Budget limits** under Providers are local advisory ceilings. Your existing Cursor Month
limit keeps its stored value; it now compares against extra-paid calendar-month spend.
Review whether that amount still suits your intended limit. A percentage needs available
spend and a positive USD ceiling. An unset ceiling differs from a saved zero ceiling, which
cannot produce a percentage. This same budget-percentage rule applies to Console and
Cursor Team choices on Watchface and Widget; it is separate from Plan on-demand Credits.
The current widget needs that percentage and does not show Team spend as amount rows.
Unavailable periods stay listed, and saved choices remain removable. Caps do not stop
requests or change the team's provider-side spending controls.

Reported **USD 0.00** means complete reporting found no rounded extra-paid spend for an
elapsed period. Unavailable or incomplete data is not zero. At a UTC period's first
millisecond there may be no elapsed reporting interval yet. **Updated** is the report's
capture time; a retained stale result keeps its original successful update time.

Recent request history and spend from **Cursor Team Admin API may take several hours or
longer to appear**. If the row shows **Connected** but recent activity is missing, wait a few
hours, then refresh again. Repeated **Refresh** taps cannot make Cursor publish reports sooner.

Cursor documents [hourly aggregation](https://cursor.com/docs/api), not a guarantee that
every request appears within an hour. **Updated** reflects WardPulse's report snapshot;
it does not mean Cursor has included all recent activity.

Cursor recommends polling at most once an hour and documents a team limit of 60 requests
per minute. Choose an hourly refresh interval and avoid repeated manual refreshes. Those
limits do not promise when new activity will become available.

**Cursor plan** percentages come from a separate dashboard connection. The reporting delay
described here applies to **Team Admin API**.

## Reconnect, change or remove a connection

Cursor plan uses **Sign in again** or the Advanced paste dialog. The Team key has its own
Value, Label and Remove controls. See [connection management](/guide/providers#reconnect-change-or-remove-a-connection).
