# Provider Notes

Provider integrations should be added one at a time. The initial implementation should use deterministic mock fixtures before connecting to live APIs.

## Initial Order

1. Mock provider.
2. OpenAI Platform organization reporting.
3. Codex subscription usage directly from the phone.
4. Claude.
5. Cursor.

The order can change when API access, account type, or reporting endpoints make another provider a better first real integration.

## Integration Contract

Each provider should document:

- credential type and minimum required permissions;
- whether read-only analytics credentials are available;
- whether the credential can initiate billable actions;
- rate limits and polling guidance;
- available metrics: cost, tokens, requests, credits, daily buckets, hourly buckets, model breakdown, workspace breakdown;
- provider-side spending limit support;
- revocation path;
- redaction requirements.

## Boundary

Platform code owns transport, TLS, background scheduling, secure credential retrieval, retries, and encrypted storage. Rust owns parsing, validation, normalization, error mapping, aggregation, budgets, projections, alerts, and dashboard view models.

### Validation stops short of rejecting timestamps

Rust validates what it can act on. It deliberately does **not** reject a malformed instant:
`DateTimeUtc` normalizes what it recognizes and passes anything else through unchanged.

The reason is the failure mode, not the type. Instants arrive inside provider payloads, so a
fallible parse would fail the whole report over one field, and a local-first dashboard would
show an error page instead of the data it already has. A single odd date is the cheaper loss.

The cost is that `DateTimeUtc` guarantees less than its name suggests, and time ordering relies
on every producer emitting RFC 3339 in UTC. If a provider ever breaks that, reject at the FFI
boundary, which already returns an error envelope — not inside the core, which has no way to
report anything.

## Consumption display

Providers may report plan allowances, purchased tokens or credits, or both. These values stay
separate from monetary budgets because their units and reset rules differ.

- Plan usage, purchased usage, and platform spend are all shown; none of the three is hideable.
  A surface the user cannot see is a surface nobody can act on, and the phone already shows only
  what providers report.
- Platform spend is phone-dashboard only: the watch carries percentages, not currency.
- WardPulse does not invent a limit, balance, or percentage when the provider omits it.
- Exact provider quantities cross shared contracts as decimal strings with an explicit `tokens`
  or `credits` unit.
- Phone dashboard accounts share a **family container** (OpenAI, Anthropic or Cursor).
  Plan and reporting accounts retain independent histories, periods, units, model detail
  and status. There is no combined Plan/API balance; plan and purchased values are never
  summed across providers into one card.
- Wear / WFF strips show remaining **purchased credits** per ring family from watch summary
  `allowances` (same lookup as Glance: `Codex · …`, `Claude · …`). Compact on the face
  (`% · 320`); Glance keeps the unit (`% left · 320 credits`). Schema `creditsGlance` remains
  for credits-only faces (no plan rings). LLM token totals stay on phone history charts —
  never as face `TOK` labels.

### The credits channel carries only credits (2026-10-11)

The two bullets above are in tension and the code resolved them the wrong way. The contract
carries `tokens` or `credits`; the watch channel is specified in credits and every baseline that
owns one of its surfaces refuses token counts by name (`WATCH_RING_DESIGN.md`, Palette and
Non-goals; `WEAR_GLANCE_DESIGN.md`, Composition; `PHONE_WIDGET_DESIGN.md`). Between the two sat
`purchasedRemainingForRing` in `GlanceModels.kt`, which matched a purchased allowance on source,
label and nothing else, and rendered whatever unit arrived. A balance reported in tokens would
have reached the Glance row as `… tokens`, and the face strip and the complication as a bare
number read as credits.

**The unit is now part of the match**, in that one lookup, which is the only path behind all
three surfaces. A purchased balance in any other unit is treated as absent — a state all three
already draw: the Glance omits the suffix, the strip and the complication show the percentage
alone. The phone has filtered on the same unit since `credit_request_runway.dart`, which is why
its home widget can hardcode the word `credits`; this is the watch side of a guard the phone
already had.

Nothing in the repository constructs `QuantityUnit::Tokens` — every adapter reports credits,
verified 2026-10-11 — so **the enum is deliberately not narrowed**. Three reasons. The first
bullet of this section says a provider may report purchased tokens, and deleting the variant
would delete that decision on the strength of adapters that happen not to exist yet.
`WATCH_RING_DESIGN.md` reserves token totals for phone history charts, a surface the product
intends rather than forbids. And `schemas/watch_dashboard_summary.schema.json` reaches the
snapshot's `quantity` by `$ref`, so narrowing the enum would narrow the **versioned** watch
payload too — `schemaVersion` 9, which `WatchSummaryStore` enforces with a hard `require` — a
breaking change to a shared contract in exchange for deleting a variant that now costs nothing.

Nor is it rejected on arrival. `QUANTITY_UNITS` in `WatchSummaryStore` still admits both,
because the alternative is failing the whole payload over one field — the same trade this
document settles for timestamps above, and the watch would show a stale summary instead of a
current one minus a credits suffix.

The guard is the purchased-credits channel only. A **plan** window reporting a bare remainder
keeps whatever unit it carries on the plan-windows page (`apps/wear_android/README.md`): that is
a detail screen rather than a glanceable legend, it names no credits, and no baseline forbids a
unit there.

## Capability-adaptive presentation

The dashboard renders only the metrics that the currently connected providers can report. The
per-provider capability tables below are the source of truth for what each connection contributes.

- A metric no connected provider supports is hidden, not rendered as a placeholder. One row keeps a
  `?` affordance that names the connection to add and deep-links to Providers.
- `Unknown` is reserved for transient provider state: a connection that has not synced yet or whose
  last sync failed. It stays on the status indicator rather than on values.
- With no connections configured, the dashboard shows a single "Connect a provider" call to action.
- Debug **Mock data** loads a seeded multi-provider demo (OpenAI, Codex, Claude plan + platform,
  Cursor plan + platform) so the full dashboard stays reviewable without live credentials.
  Utilization reshuffles on toggle/refresh (not on automatic sync ticks); the Phase 1 single
  `provider: mock` golden remains for CLI/FFI regression only. Platform accounts come from the
  real adapters, which report spend but never a limit, so the demo derives a stand-in ceiling
  from the fixture's own spend and keeps it short of exhaustion — an invented limit must not
  stage an `Error`.

## Polling cadence

Per-connection minimum intervals live in Rust (`ward-pulse-providers::poll`) with doc-linked
comments, and are the single source of truth for cadence:

- one global refresh slider from 5 to 60 minutes (strictest hard floor rounded up), segmented as
  5–15 by 1 minute, 15–30 by 5, and 30–60 by 10, so a single global cadence already satisfies
  every per-connection floor;
- `effective_interval = max(user_setting, provider_minimum)` per connection;
- automatic sync on the phone runs on an in-process scheduler while the app isolate is alive
  (full 5–60 minute slider); after Android reclaims the process, a WorkManager Dart
  entrypoint continues sync at `max(slider, 15 minutes)` (Android periodic minimum);
- watch summary re-sent after each successful automatic sync;
- a failed sync keeps the last successful snapshot visible and retries on the next tick, so a
  launch without connectivity still recovers without a manual refresh;
- the Cursor Team Admin API row shows a freshness note that usage may lag about an hour (documented
  provider-side hourly aggregation); that note does not clamp the cadence and is not shown on the
  experimental Cursor plan row;
- existing `429` / `Retry-After` / backoff handling still applies on top of the cadence;
  waits longer than five seconds are not slept in-process — the sync fails as rate-limited and
  the next scheduled tick retries, so a long provider cooldown never stalls the dashboard.

Reporting endpoints are rate-limited independently from model inference: polling usage never slows
a running agent.

## Connection grouping

Every family on the **Providers** tab is one section with distinct Plan and reporting connections:

- `plan`: subscription or allowance reads (Codex device-code OAuth; Claude Code PKCE OAuth
  with authorization-code paste from the callback page; Cursor dashboard WebView sign-in that
  captures `WorkosCursorSessionToken`, with optional Advanced paste);
- `platform`: organization or team usage and cost reporting with provider-appropriate keys
  and reporting access.

The current user-facing plan names are **Codex plan**, **Claude plan** and **Cursor plan**.
OpenAI groups Codex plan with Platform reporting; Anthropic groups Claude plan with
Organization reporting; Cursor groups Cursor plan with Team Admin API. The Dashboard
uses the same family grouping while keeping each account's data and status separate.
A plan login does not grant reporting access or verify its sibling reporting key.
An optional user-defined label for reporting keys is plain phone-local display metadata:

- stored beside the credential reference, never concatenated into the secure key value;
- shown on the Providers row alongside its canonical family-and-kind identity;
- removed when the credential is removed;
- never sent to Wear OS or the watch face.

Existing stored keys remain in place after the connection-catalog move from Settings to
Providers; users do not need to re-enter them.

Reporting-key presence and verification are separate. `ConnectionReportingOutcome` binds
a result to the exact connection and current credential/cache version; only a successful
current result can show Connected. Saving or replacing a key requests one existing live
load through the shared reporting/cache lifecycle. `ConnectionReportingUpdate` and the
app own completion across Providers disposal or tab changes. Removal or a later version
invalidates obsolete outcomes. Label-only edits keep the key and verification without
another live check; a saved key still receives its check if later Label persistence fails.

Dashboard and Providers show the same connection-specific sanitized category: authentication,
access denial, transient failure, rate limit, invalid response or local credential-read failure.
Cached previous data, a sibling plan and mock accounts cannot verify a replacement key.
There is no prevalidator or duplicate validation poll. Debug mock mode that suppresses live
reporting leaves the key Not verified without adding network requests. The Dashboard's
[named-feedback rules](PHONE_DASHBOARD_DESIGN.md#reporting-key-feedback) preserve existing
severity, family identity and rollup counts.

## OpenAI Platform organization reporting

Status: selected as the first live provider contract on 2026-07-19.

Scope:

- Target OpenAI Platform organization usage and cost reporting. Do not assume that this API includes personal ChatGPT or Codex subscription usage.
- Use an organization Admin API key with access to both reporting endpoints. Their published API contract requires `AdminApiKeyAuth`; an ordinary project API key configured as read-only is not sufficient. Treat the key as a privileged administrative secret and store it only in phone-secure storage.
- Send `GET` requests only. The key cannot call non-administration endpoints or run model inference, so this adapter cannot initiate billable model work; unrelated administrative privileges may still be present.
- Fetch completions usage from `GET /v1/organization/usage/completions` and cost from `GET /v1/organization/costs`.
- Request daily buckets for dashboard cost. Usage also supports hourly buckets and grouping by model, project, or user; cost supports daily buckets and grouping by project, line item, or API key.
- Follow response pagination. Automatic polling uses the global refresh slider, whose 5-minute
  lower bound already sits at this adapter's floor, so it never syncs more than once every five
  minutes. After `429`, honor short `Retry-After` values and otherwise apply exponential
  backoff with jitter; waits longer than five seconds defer to the next scheduled sync.
- Keep budgets local. This adapter reads reporting data and does not manage provider-side spending limits or spend alerts.
- Never log the key, authorization header, full account identifiers, or raw response bodies.

Capabilities:

| Metric | Support | Notes |
| --- | --- | --- |
| Cost | Yes | Daily buckets from the Costs API. |
| Tokens and requests | Yes | Completions usage supports both. |
| Credits | No | No credit-grant reporting endpoint is part of this adapter. |
| Daily usage buckets | Yes | Completions usage supports daily aggregation. |
| Hourly usage buckets | Yes | Completions usage supports hourly aggregation. |
| Daily cost buckets | Yes | The Costs API supports daily aggregation. |
| Hourly cost buckets | No | The Costs API supports daily aggregation only. |
| Usage model breakdown | Yes | Usage can group by model. |
| Cost model breakdown | No | Cost cannot group by model. |
| Workspace breakdown | No | Project and user grouping must not be presented as workspace reporting. |
| Active agents | No | Reporting data is not live agent state. |

Revocation is performed in OpenAI Admin API key settings. OpenAI RBAC exposes a `Usage` read permission, but the reporting endpoints still require Admin API key authentication. WardPulse must therefore describe the credential as an organization Admin API key rather than a project read-only key.

Implementation status as of 2026-07-19:

- The phone stores the key with platform-secure storage and never reads it back into the credential field.
- The credential field can reveal only the current unsaved value after an explicit user action; saved credentials remain masked.
- Android backup is disabled so encrypted values cannot be restored without their device-bound key.
- Usage and cost pages are fetched directly from the phone, then passed without credentials or authorization headers to the Rust normalization boundary.
- OpenAI API costs are normalized as USD. Raw page JSON crosses the Dart-to-Rust boundary as strings so decimal values remain exact; Rust sums exact values before rounding period totals to cents. Missing optional amount fields are ignored and an empty successful cost report is represented as zero spend.
- Cost amounts accept both JSON numbers and decimal strings because the live Costs API may use either representation.
- Sync diagnostics contain only the endpoint label, HTTP status, provider error code, request ID, or a sanitized parser reason. Provider response bodies are processed in memory and are not logged.
- Authentication, permission, rate-limit, availability, and response-shape failures are mapped to fixed UI-safe messages without response bodies or credentials.
- Sanitized fixtures cover report parsing; live acceptance requires a user-supplied Admin API key.

Official references:

- [Administration overview](https://developers.openai.com/api/reference/administration/overview)
- [Organization completions usage](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/completions)
- [Organization costs](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs)

## Codex subscription reporting

Status: implemented as an experimental on-device integration on 2026-07-19; Android end-to-end
acceptance taken **2026-10-12** on the canonical emulator pair, `wardpulse_phone_play_api36` and
`wardpulse_wear_round_api36_1`.

What was seen: a live Codex connection feeding the phone Dashboard — the `Weekly plan` window,
the purchased credit balance, and a 31-bucket `Usage history`, which is exactly the *Latest 31
daily buckets* the capability table below promises — while the same payload reached the home
widget and the watch face's third band and strip, and a provider-side change propagated to all
of them with nothing touched. That is the read path end to end across the Android stack, so the
line is no longer pending.

Two things it does not cover, and neither is a reason to hold this line open. The device-code
sign-in was already established rather than re-exercised in that session, so the authentication
path has its own evidence from 2026-07-19 and not this reading. And both ends were emulators;
shipped watch and phone hardware remain untested, which is Phase 8's *real device smoke tests*
rather than this integration's.

Phase 7's acceptance line in `docs/DEVELOPMENT_PLAN.md` asks for more than this one does — it
bundles signing in from the Providers connection catalog with verifying the live phone and watch
UI. The second half is what 2026-10-12 covers; the first is why that phase still reads as
pending.

The OpenAI Platform Admin API does not represent personal Codex subscription limits. WardPulse
therefore treats Codex as a separate provider. The phone reproduces only the narrow authentication
and read paths used by the open-source Codex client:

- OpenAI device-code sign-in and OAuth token refresh;
- `GET /backend-api/wham/usage` for plan windows and purchased credit balance;
- `GET /backend-api/wham/profiles/me` for daily token activity.

The access token, rotating refresh token, and account routing identifier stay in platform-secure
storage. The client retries once after refreshing an expired token, retains at most the latest 31
daily buckets, and discards profile identity fields. Refresh and report operations are serialized,
and every rotated token is saved before reporting continues. No Codex CLI, desktop process,
loopback server, or WardPulse cloud service is involved.

When both Codex and OpenAI Platform are configured, the phone fetches them independently and Rust
rebuilds one dashboard from both provider snapshots. A failure in one provider leaves current data
from the other provider visible with the failed sync identified.

This is a compatibility integration, not a published third-party API contract. Endpoint or OAuth
changes may require an app update. WardPulse must surface that failure without exposing tokens or
raw responses and must not expand this path into model execution or general ChatGPT access.

The usage response keeps the unnamed main limit in the root `rate_limit`, puts separately metered
limits in `additional_rate_limits` with `limit_name`, `metered_feature`, and a nested `rate_limit`,
and reports `credits` once at the response root. The phone keeps the main limit under the local id
`codex`, retains credits only on that root report record, and builds the report's
`rateLimitsByLimitId` map from the main limit plus known additional limits. Additional limits are
recognized by a local `metered_feature` table: `codex_bengalfox` maps to `spark` / `Spark`. The
API's versioned `limit_name` is not a stable label, and an unknown feature is omitted until the
table is updated rather than exposed under an internal code name.

A limit that carries a name labels both of its windows after itself, so a limit reporting two of
them would label them identically. A named limit reporting both therefore appends the short window
token a watch row can carry — `Spark 5h`, `Spark Weekly`. The token joins with a space rather than
` · `, because that separator already means family-then-pool wherever a label is read: one inside a
pool name would leave the Glance row without its family and the ring picker without its pool. An
unnamed limit takes no token: it falls back to the window's own name, which already says which
window it is, and appending to that would rewrite the locked `Codex · Weekly plan` row for every
account reporting one.

Capabilities:

| Metric | Support | Notes |
| --- | --- | --- |
| Plan usage | Yes | Primary and secondary rate-limit windows when reported. |
| Purchased credits | Yes | Includes finite balances and explicitly unlimited balances. |
| Token activity | Yes | Latest 31 daily buckets. |
| Platform API cost | No | Remains the separate OpenAI Platform provider. |
| Requests or model breakdown | No | Not exposed by these account methods. |

Official references:

- [Codex app-server authentication and account methods](https://learn.chatgpt.com/docs/app-server#auth-endpoints)
- [Open-source Codex device-code implementation](https://github.com/openai/codex/blob/main/codex-rs/login/src/device_code_auth.rs)
- [Open-source Codex backend client](https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/client.rs)

## Anthropic organization reporting

Status: implemented on 2026-07-25.

Checked 2026-10-16: the official [Usage and Cost guide](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)
permits Admin keys, OAuth with `org:admin`, and personal/service keys that are not
workspace-scoped, with the required organization reporting rights. Workspace-scoped keys
do not work. This key-entry integration does not add a reporting OAuth flow; a key prefix
or personal ownership alone does not establish reporting access.

Individual Console API organizations do not have Admin API access. The Console flow
observed on 2026-10-17 was **Settings → Organization → Convert to team organization →
Convert to team**, followed by organization details and API-use questions. Choosing
**Scope: Organization** on a key does not change the organization's type. This conversion
is separate from buying a claude.ai Team chat plan. The owner reported a successful
reporting connection after conversion; that report is not an independent new API probe
or a guarantee of eligibility, free conversion or reversal for other accounts.

Organization-scoped personal keys use the linked account's reporting permissions;
eligible service-account keys must also be outside workspace scope. Console Admin keys
are a separate supported type without the personal-key Scope selector. Claude Enterprise
Analytics keys are for another service. None of these reporting credentials replaces the
separate **Claude plan** login.

Scope:

- Use a key with organization reporting access (`x-api-key`) against
  `GET /v1/organizations/usage_report/messages` and `GET /v1/organizations/cost_report`.
- Fetch historical usage in daily buckets (`bucket_width=1d`, limit 31), ending at the
  supplied snapshot end's UTC midnight. Fetch only the requested current-day intersection
  in completed minute buckets (`bucket_width=1m`, limit 1440), through the actual snapshot
  end. Skip empty ranges and paginate both widths; never extend the end into the future.
- Usage requests `group_by[]=model` for model breakdown; cost stays ungrouped.
- Costs keep daily aggregation over the original requested interval. Amounts are decimal
  strings in lowest currency units (cents); WardPulse rounds reported amounts to integer
  USD cents without estimating prices from tokens.
- Rust coalesces minute usage into one UTC-day history bucket ending at the latest reported
  bucket end, preserving model/cache totals and historical daily cost alignment. Reported
  zero remains known zero; absent cost stays unknown in history and affected period totals.
  API token history can appear before reported costs; no reporting deadline is promised.
- Documented poll floor is one minute; the global slider lower bound remains five minutes.
- Never log the key, authorization header, or raw response bodies.

Verified 2026-10-20: host Rust, fixture, Flutter and documentation checks passed, followed by
both Android Rust builds, a debug phone APK build and a preserving installation. Live phone
history changed from 19 daily buckets with USD 0.00 to 20 buckets with 39 reported tokens;
the model rows showed Haiku 4.5 with 16 tokens and Opus 5.5 with 23. Only the Haiku request
is attributed to the scoped test. Selected plan allowances remained consistent on the phone
widget, Wear Glance and watch face after a fresh sync. API budgets were not configured on
those surfaces, so this does not claim that they rendered the API token history.

Revoke the key through the appropriate Console key-management controls for its type.

Official references:

- [Usage & Cost Admin API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)
- [Console organization settings](https://platform.claude.com/settings/organization)
- [Console API keys](https://platform.claude.com/settings/keys)
- [Claude plans and separate API billing](https://support.claude.com/en/articles/9876003-i-have-a-paid-claude-subscription-pro-max-team-or-enterprise-plans-why-is-claude-api-usage-billed-separately-from-my-paid-claude-plan)
- [Messages usage report](https://platform.claude.com/docs/en/api/admin/usage_report/retrieve_messages)
- [Cost report](https://platform.claude.com/docs/en/api/admin/cost_report/retrieve)

## Claude subscription reporting

Status: implemented as an experimental on-device compatibility integration on 2026-07-25;
phone-owned PKCE sign-in landed 2026-07-26.

Anthropic does not publish a device-code grant for Claude Code. The phone runs the same PKCE
authorization-code flow Claude Code uses (`client_id` for Claude Code, redirect
`https://platform.claude.com/oauth/code/callback`): open the authorize URL, user pastes the
`CODE#STATE` value from the callback page, then the phone exchanges it for access and rotating
refresh tokens in secure storage. Refresh is serialized like Codex. Reporting calls undocumented
`GET /api/oauth/usage` with `anthropic-beta: oauth-2025-04-20` and a Claude Code user agent, then
normalizes `five_hour`, `seven_day`, optional per-model weekly windows, and `extra_usage` into
`AllowanceState`. Phone dashboard cards still list every window. Watch/Glance rings collapse
Claude **plan** windows into one slot (`allowance.claude.plan`): the tightest known remaining
window wins, including an exhausted window; unknown windows cannot displace a known zero.
Glance label is the short token (`5h`, `Weekly`, `Opus weekly`, `Sonnet weekly`). Purchased
`extra_usage` is not in that collapse pool and is **not** a watch ring candidate — it stays on
phone dashboard cards. It may surface as a warning/error alert
**only when the user configures a threshold** for that meter on Providers — never from a
hard-coded utilization cutoff alone.

Claude plan resets are validated by `claude_provider_snapshot_from_report_json` in
`core/ward-pulse-providers/src/claude/mod.rs`. Supported input is ASCII Gregorian
`YYYY-MM-DDTHH:MM:SS[.digits]` with uppercase `T` and a mandatory uppercase `Z` or numeric
`±HH:MM` zone (at most `23:59`), valid calendar dates, and no leap seconds. Years must stay
within `0000`–`9999` before and after UTC conversion. The adapter validates the entire fraction,
applies the offset, then drops sub-second precision to emit `YYYY-MM-DDTHH:MM:SSZ`.
Missing or null resets stay absent; malformed or overflowing resets return the sanitized
`InvalidTimestamp` adapter error. This boundary leaves the shared infallible `DateTimeUtc`
and its text-based equality and ordering policy unchanged; see [Boundary](#boundary).

This is a compatibility integration, not a published third-party API. Endpoint or OAuth client
changes may require an app update. Never log tokens, authorization codes, or raw response bodies.

## Cursor plan reporting

Status: implemented as an experimental on-device compatibility integration on 2026-07-25;
dashboard WebView sign-in added 2026-07-26.

Cursor has no official personal-account usage API and no OAuth grant for plan meters. Providers
opens an in-app WebView to the Cursor dashboard; after sign-in the phone captures the
`WorkosCursorSessionToken` cookie (Advanced paste remains for the same value), stores it
securely, and calls `GET /api/usage-summary`, normalizing included plan pools and on-demand
meters into allowances. When the payload includes `autoPercentUsed` / `apiPercentUsed`, WardPulse
shows **Cursor Models** and **Other Models** as separate plan bars (same as the Cursor usage UI)
on the phone and as selectable watch rings. Purchased on-demand usage is phone-only (and may
alert **only** with a user-configured threshold on Providers); it is not a ring. Older combined-only payloads keep a single Plan
usage bar. Selected known exhausted pools remain on the watch as 0% left with empty grey
tracks; unknown or unavailable pools are not fabricated as zero.
Do not claim Admin-API hourly aggregation on this experimental row. Never log the cookie or
raw response bodies.

## Cursor team Admin API

Status: implemented on 2026-07-25.

Use a team API key whose account has reporting access. Checked 2026-10-16: the official
[API overview](https://cursor.com/docs/api) lists Enterprise eligibility, while official
[Teams pricing](https://cursor.com/docs/account/teams/pricing) describes Teams usage statistics
through the Admin API. Preserve that discrepancy rather than asserting a universal
Teams-insufficient rule; actual access denial is distinct from authentication rejection.
The unified Team-key path observed on 2026-10-17 uses the intended team's
[Team API keys](https://grok.com/dashboard/api-keys/team). The tested setup clears the
preselected permissions and enables only **General → View team resources**, whose
description includes members, usage, spend, analytics, audit logs and settings. Other
permissions, including Agents/Models and write access, stay off. **View member usage**
alone was not a sufficient tested setup; do not recommend All permissions to recover
reporting. Actual stored grants and legacy scope metadata were not inspected, so the
observed menu choice does not establish a literal mapping to legacy scope names. Do not
infer a universal key prefix or administrator visibility rule from this new UI.

A Team key is distinct from a personal User key under **API & SSH Keys** and from the
**Cursor plan** dashboard login. A personal Premium subscription does not confirm that a
team exists or has reporting access. The observed creation path is **Get Teams** on the
[official pricing page](https://x.ai/pricing); an already-paid Premium account looping
through Start a team/Unify used the
[Premium team-creation entry](https://grok.com/dashboard/members?modal=create-team&tier=premium).
Admin is a role; Premium is a paid seat. One person can hold both. Assigning an already
purchased unused seat differs from buying or upgrading one; review billing before any change.

Before confirming **Unify**, verify the Cursor, Grok and optional X accounts shown:
[completed unification cannot be undone](https://docs.x.ai/x-subscription/unify-accounts).
[Moving a legacy Cursor plan to The X Subscription](https://cursor.com/docs/account/pricing/legacy-cursor-plans)
is separately permanent. A separate account can leave an existing account and legacy plan
unchanged. None of these observations guarantees reporting eligibility for every team or plan.

Reporting outcomes:

An explicit missing-reporting-scope response is **access denial**, distinct from an
authentication rejection. A successful ordinary empty daily report can have no history;
paginated inactive days containing only zero counts are not evidence of usage. Connected
does not promise activity or immediate changes to the history. Provider-side hourly
aggregation is not an exact publication deadline. The phone's `CursorPlatformClient.fetchReports`
in `apps/phone_flutter/lib/sync/provider_reporting_clients.dart` owns retrieval;
`_isMissingCursorReportingScope` in `apps/phone_flutter/lib/sync/provider_reporting.dart`
identifies the explicit missing-scope response for error mapping;
`cursor_platform_snapshot_from_report_json` in
`core/ward-pulse-providers/src/cursor/platform.rs` owns normalization.

Scope:

- Basic auth with a team Admin API key against `POST /teams/daily-usage-data` and
  `POST /teams/spend`.
- Spend responses use `teamMemberSpend` (also accepted as `teamMembers`) with
  `page` / `pageSize` pagination. For each member, `overallSpendCents` takes precedence,
  including zero; otherwise both `includedSpendCents` and `spendCents` must be reported
  and their sum is the total. Round the selected member total once to integer cents,
  reject non-finite or out-of-range totals, then checked-add across members and pages.
  Missing/null collections, no spend pages or incomplete member amounts leave the month
  spend unknown. Explicit empty collections and complete zero amounts remain known zero;
  malformed collections are rejected.
- Spend is billing-cycle scoped and maps only to the month budget; today and week stay
  unknown until a day-scoped spend source exists.
- Daily request counts are raw usage events, not billed request units. Count only the complete
  funding family `subscriptionIncludedReqs + usageBasedReqs + apiKeyReqs`; the overlapping
  `composerRequests`, `chatRequests` and `agentRequests` breakdown is ignored. Explicit
  canonical zeros stay known zero. An incomplete funding family makes that day's count
  unknown across all rows and pages; complete counts retain saturating addition and UTC dates.
- Hard ceiling is 20 requests per minute; WardPulse polls at the global slider cadence (minimum
  five minutes). Usage aggregates hourly on the provider side; Providers shows that freshness
  note on this Admin API row only.
- Never log the key, authorization header, or raw response bodies.

Official references:

- [Cursor API overview](https://cursor.com/docs/api)
- [Team Admin API](https://cursor.com/docs/account/teams/admin-api)
- [Staff clarification of per-member and pooled spend](https://forum.cursor.com/t/admin-api-docs-missing-includedspendcents-and-new-teams-usage-metrics/162742/9)
- [Team roles, seats and invitations](https://docs.x.ai/x-subscription/team-plans)

Verified 2026-10-20: the normalization corrections passed host checks and a preserving phone
update; the selected plan allowances were checked on the phone widget, Wear Glance and watch
face after fresh sync. These checks do not establish positive Team ledger activity or which
team paid for the personal CLI test. The owner subsequently confirmed a current paid seat;
the exact tier and seat state during the earlier test were not independently verified. The
installed CLI computes team selectability locally from direct membership, billing metadata
and a positive seat count; its listed team remains unselectable despite that owner report.
This metadata discrepancy, the empty live Team ledger and the earlier test's billed context
remain unresolved. No publication deadline, current Free seat or billing cause is inferred.
