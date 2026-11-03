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

**Current Claude scope, 2026-11-03.** Claude Plan monthly Extra usage is the offered expense
source; Console/API reporting is future work. Its reported used amount, applicable cap and
percentage are independent. Keep the existing Credits conversion as a compatibility choice,
not a documented wire-unit or USD contract. Infer no wallet, missing amount, unlimited state,
daily history, timezone or monthly reset. There is no tier-name gate or all-tier live certification.

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
- the Cursor Team Admin API row notes hourly provider-side aggregation and that refreshed values
  may lag; it does not promise publication within an hour, clamp the cadence or appear on the
  experimental Cursor plan row;
- existing `429` / `Retry-After` / backoff handling still applies on top of the cadence;
  waits longer than five seconds are not slept in-process — the sync fails as rate-limited and
  the next scheduled tick retries, so a long provider cooldown never stalls the dashboard.

Reporting endpoints are rate-limited independently from model inference: polling usage never slows
a running agent.

## Connection grouping

Every family on the **Providers** tab is one section. Supported connection kinds are:

- `plan`: subscription or allowance reads (Codex device-code OAuth; Claude Code PKCE OAuth
  with authorization-code paste from the callback page; Cursor dashboard WebView sign-in that
  captures `WorkosCursorSessionToken`, with optional Advanced paste);
- `platform`: organization or team usage and cost reporting with provider-appropriate keys
  and reporting access.

The current user-facing plan names are **Codex plan**, **Claude plan** and **Cursor plan**.
OpenAI groups Codex plan with Platform reporting; Anthropic currently offers Claude plan
only; Cursor groups Cursor plan with Team Admin API. Organization reporting is deferred.
The Dashboard uses the same family grouping while keeping each account's data and status separate.
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

**Current-scope qualification, 2026-11-03.** Console/API reporting is deferred from the
active catalogue and the shared foreground/headless collection stack. Retained collectors,
normalization and dated qualification below are backend/history evidence, not acceptance
of current Console expense support. Stable connection/backend IDs, saved credentials,
labels, cache identities/generations and settings remain; deferral performs no reset,
deletion or reauthentication. Other reporting providers and shared helpers remain active.

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
- Costs use daily aggregation. The documented `ending_at` selector filters bucket ends,
  so collection sends one second after the captured end's UTC ceiling midnight; an exact
  midnight uses that midnight plus one second. This selection fence admits the last required
  daily bucket without moving the snapshot's as-of time or implying future activity.
  `buildLiveProviderStack` in `apps/phone_flutter/lib/dashboard/live_provider_stack.dart`
  carries the captured `generatedAt` and private integer `capturedEndMicros` together.
  `anthropic_provider_snapshot_from_report_json` in
  `core/ward-pulse-providers/src/claude/platform.rs` uses the precise bound instead of the
  shared whole-second timestamp when selecting cost days and deciding empty periods.
  Amounts are decimal strings in lowest currency units (cents); WardPulse rounds them to integer
  USD cents without estimating prices from tokens.
- Rust coalesces minute usage into one UTC-day history bucket ending at the latest reported
  usage or cost bucket end, preserving model/cache totals and daily cost alignment. A
  current-day cost bucket retains its nominal next-midnight end, not an inferred publication
  cutoff. Cost days outside the requested interval, including days starting at the precise
  captured end, do not contribute.
- Today, Monday-start Week and calendar Month are UTC periods for the authorized organization.
  Each total requires cost coverage for every intersecting UTC day, even a day absent from
  usage. An empty period is unavailable. A returned empty cost bucket or explicit zero is
  known zero; an absent day or missing result amount leaves the affected total unavailable.
  API token history can appear before reported costs; no reporting deadline is promised.
- Budget percentages compare reported-to-date spend with locally saved advisory ceilings;
  they do not promise that every incurred charge has been published or enforce provider-side
  limits. Supported Anthropic period IDs remain disabled in the selection catalogue when
  spend is unavailable, separately from an unset or unusable ceiling. Saved selections and
  ceiling values are retained; plan connections gain no monetary budget rows.
- Documented poll floor is one minute; the global slider lower bound remains five minutes.
- Never log the key, authorization header, or raw response bodies.

The cost bucket-end selection contract was supplied from the
[legacy cost reference](https://platform.claude.com/docs/en/api/beta/organization/cost_report/retrieve) on
2026-11-02. That current reference presents API version `2026-10-21`; this integration
retains `anthropic-version: 2023-06-01`. Acceptance of the corrected fence under the deployed
header still requires bounded actual-response verification. Source and synthetic regressions,
and the historical verification below, do not establish fresh live cost availability.

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
`AllowanceState`. Optional `five_hour` and all other ordinary/Fable windows normalize
independently; an absent session does not hide the remaining windows or extra usage.
Phone dashboard cards still list every reported window. Watch/Glance rings collapse
ordinary Claude **plan** windows into one slot (`allowance.claude.plan`): the tightest known
remaining window wins, including an exhausted window; unknown windows cannot displace a known zero.
Glance label is the short token (`5h`, `Weekly`, `Opus weekly`, `Sonnet weekly`). Purchased
`extra_usage` is not in that collapse pool and is **not** a watch ring candidate — it stays on
the phone Dashboard as monthly used/applicable-cap Credits. The phone widget retains
reported finite nonnegative-percentage eligibility even with no cap, using stable ID
`allowance.claude.claude-extra-usage`. Missing/invalid percentage produces no widget row;
saved unavailable choices remain removable. Monthly used/cap widget details remain pending
the separately approved runtime adoption. It may surface as a warning/error alert
**only when the user configures a threshold** for that meter on Providers — never from a
hard-coded utilization cutoff alone.

The optional included Fable weekly sub-cap is normalized independently as
`claude-seven-day-fable` (`Fable weekly`), never as an Opus alias. The adapter joins
`weekly_scoped_shares[].limit_index` to that response's `limits` array, requiring a
nonnegative integer index, kind `weekly_scoped`, group `weekly`, an explicitly null
`scope.model.id` and exact `scope.model.display_name` of `Fable`. It emits at most one
Fable allowance. Missing/null lists, malformed entries and unknown scopes do not invalidate
independently valid ordinary or legacy windows.

Own-quota used percentage is inferred only from `used_percent_of_weekly` divided by
`allowance_percent_of_weekly`, then multiplied by 100. Usage must be finite and nonnegative;
the allowance must be finite and positive. Usage at or above the allowance becomes 100%;
otherwise division precedes multiplication to avoid overflow. Invalid or missing inputs
leave usage and status unknown. Neither a fixed allocation nor `limits.percent`, activity,
severity or a sibling window supplies a fallback.

This is a narrow inference from explicit weekly-relative fields and Anthropic's
[included shared-weekly sub-cap policy](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan),
not a published private-API guarantee. The 2026-11-01 safe observations show null scoped
shares on Pro and a recognized join after an owner-reported Max upgrade: 0 used / 50
allowance, with `is_active=false`. Ordinary weekly usage is also inactive at zero, so activity
does not establish availability or consumption. All observed consumption is zero; neither
the denominator of `limits.percent` nor precise activity semantics is established.
The Pro/Max fixtures are explicitly synthetic projections of the three allowlisted safe
observations/field-shape/measurement files. Nonzero arithmetic tests are synthetic, not
captured positive-consumption evidence.

Providers exposes each reported Plan window for its own alert rule, independently of
watch collapse or selection. A window inherits the connection's Plan threshold unless it
has an explicit percentage or Off override. See the user guide's
[Alert thresholds](user-guide/DASHBOARD.md#alert-thresholds).

Claude plan resets are validated by `claude_provider_snapshot_from_report_json` in
`core/ward-pulse-providers/src/claude/mod.rs`. Supported input is ASCII Gregorian
`YYYY-MM-DDTHH:MM:SS[.digits]` with uppercase `T` and a mandatory uppercase `Z` or numeric
`±HH:MM` zone (at most `23:59`), valid calendar dates, and no leap seconds. Years must stay
within `0000`–`9999` before and after UTC conversion. The adapter validates the entire fraction,
applies the offset, then drops sub-second precision to emit `YYYY-MM-DDTHH:MM:SSZ`.
Missing or null resets stay absent; malformed or overflowing resets return the sanitized
`InvalidTimestamp` adapter error for ordinary and legacy windows. Optional Fable uses only
its joined limit's own reset through the same parser; missing, malformed or overflowing
Fable resets stay absent without discarding ordinary windows or borrowing their reset.
This boundary leaves the shared infallible `DateTimeUtc` and its text-based equality and
ordering policy unchanged; see [Boundary](#boundary).

This is a compatibility integration, not a published third-party API. Endpoint or OAuth client
changes may require an app update. Never log tokens, authorization codes, or raw response bodies.

## Cursor plan reporting

Status: implemented as an experimental on-device compatibility integration on 2026-07-25;
dashboard WebView sign-in added 2026-07-26.

The reviewed official [API](https://cursor.com/docs/api) and
[SDK](https://cursor.com/docs/sdk/typescript) documentation does not establish an equivalent
authorization grant for this integration’s personal plan meters. SDK User API keys and agent
usage are separate from dashboard plan reporting and Team reporting. Providers opens an in-app
WebView to the Cursor dashboard; after sign-in the phone captures the
`WorkosCursorSessionToken` cookie (Advanced paste remains for the same value), stores it
securely, and calls `GET /api/usage-summary`, normalizing included plan pools and on-demand
meters into allowances. When the payload includes `autoPercentUsed` / `apiPercentUsed`, WardPulse
shows **Cursor Models** and **Other Models** as separate plan bars (same as the Cursor usage UI)
on the phone and as selectable watch rings. Purchased on-demand usage is phone-only (and may
alert **only** with a user-configured threshold on Providers); it is not a ring. Older combined-only payloads keep a single Plan
usage bar. Selected known exhausted pools remain on the watch as 0% left with empty grey
tracks; unknown or unavailable pools are not fabricated as zero.

Both included pools remain Plan windows for alert configuration, independently of watch
selection. Each can inherit Plan, set its own percentage or explicitly turn Off;
Purchased controls the separate on-demand allowance. See
[Alert thresholds](user-guide/DASHBOARD.md#alert-thresholds).

Navigation additionally admits only the six exact HTTPS identities in Cursor's
[sign-in-domain guidance](https://cursor.com/help/troubleshooting/sign-in-domains), reviewed
2026-10-27: `accounts.x.ai`, `accounts.spacex.ai`, `auth.x.ai`, `auth.grok.com`,
`auth.grokusercontent.com` and `auth.grokipedia.com`. The page's October 30 fallback wording
supplies no year. These hosts gain no credential-read authority: cookie reads/probes remain
HTTPS `cursor.com` apex/subdomains only.

The navigation policy rejects Google authorization in accordance with Google's
[secure-browser policy](https://developers.google.com/identity/protocols/oauth2/policies#use-secure-browsers).
Android's `CursorSignInWebViewClient` in
`apps/phone_flutter/android/app/src/main/java/app/wardpulse/CursorSignInWebViewClient.java`
wraps the plugin client to block authorization navigation and resource requests, including
subframes that the Flutter delegate does not expose. Native interception enforces the same
approved main-frame HTTPS/host policy for all request methods, including POST, which skips
Android's navigation callback. The internal blank document is admitted only after retirement
begins. Harmless CAPTCHA/static subresources still reach the original client. Native main-frame HTTP failures enter page recovery; optional
subresource HTTP errors do not. The guard crosses only view/client IDs and fixed failure
categories, and its sticky status is checked before/after cookie probing and before accepting completion.
The WebView keeps its default user agent. Recovery uses
same-account email when offered, Cancel/reopen and Help → Advanced paste, without a new
browser handoff or OAuth protocol.
External browser return does not supply the WebView cookie; no suitable reporting
callback/exchange was established for this integration.

`CursorPlanSignInScreen` in `apps/phone_flutter/lib/providers/cursor_plan_sign_in_screen.dart`
bounds platform stages to 15 seconds and page loading to 30 seconds. Two minutes bounds
automatic polling, then Check again resumes checks while password/MFA entry remains waiting.
Retry verifies a new startup wipe; old work retains the shared-jar lease until it settles and
its document finishes retiring to a local blank page. Unsettled cleanup cannot clear a newer
attempt. Failure/cancellation leaves the previous saved connection intact. A token is returned
only once after verified cleanup. A failed blank-page request is retryable: the barrier
retains the old browser until retirement succeeds, including on Retry or Cancel/reopen.
A failed retirement never grants a newer browser access to the shared jar.

Local verification on 2026-10-27–28 passed the complete phone check, affected Flutter
regressions and native callback JVM harness. Normal and seeded debug APKs were built
and installed with data preserved on the API36 phone emulator. Native offline page recovery,
Retry, Cancel/back/reopen, Help and the empty Advanced paste route were observed;
the normal build repeated page recovery and Cancel after the debug-seed bootstrap change.
Saved-connection presence remained intact; its secret value was not inspected.
The four Help/Paste captures use a shared Mock reference, not live-provider acceptance.

Current Google/email migration, external browser return, new live session capture,
account entitlement and live-provider acceptance remain **Pending**. Source/fake tests
do not establish live login success, and these changes do not establish a billing repair.
Do not claim Admin-API hourly aggregation or a Team publication deadline on this experimental
row. Never log auth query/fragment, identity/password, tokens, cookies/headers or raw bodies.

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
does not promise activity or immediate changes to the history. Cursor Team Admin API request
history and spend may take several hours or longer to appear. When Connected but recent
activity is missing, the user guide recommends waiting a few hours before another refresh;
this is a practical retry interval, not a measured minimum or publication guarantee. Provider-side
hourly aggregation is not an exact publication deadline. These observations do not measure
the freshness of the separate Cursor plan percentages. The phone's `CursorPlatformClient.fetchReports`
in `apps/phone_flutter/lib/sync/provider_reporting_clients.dart` owns retrieval;
`_isMissingCursorReportingScope` in `apps/phone_flutter/lib/sync/provider_reporting.dart`
identifies the explicit missing-scope response for error mapping;
`cursor_platform_snapshot_from_report_json` in
`core/ward-pulse-providers/src/cursor/platform.rs` owns normalization.

Scope:

- Basic auth with a team Admin API key against `POST /teams/daily-usage-data` and
  `POST /teams/filtered-usage-events`. Money covers the authorized team's extra-paid usage,
  not an inferred personal account. Only explicit `isChargeable: true` events contribute
  numeric `chargedCents`, including Cursor fees. Included/nonchargeable usage is excluded
  even when its reported amount is positive; request units and model costs are not money.
- One captured UTC instant defines Today, Monday Week and calendar Month. The event query
  starts at the earlier Week/Month start and ends inclusively one millisecond before the
  captured instant floored to epoch milliseconds. STRING epoch-ms event timestamps and
  numeric inclusive period echoes keep their exact time meaning. Each period independently
  requires positive integer-ms duration; an empty shorter period stays Unknown even when
  a wider query is valid. The independent 14-day daily history window is unchanged.
- Validate event page identities, explicit flags, echoed bounds, stable counts and page size
  (1000), and terminal aggregate row count in both Dart and Rust. Partial and empty pages
  are allowed; there is no fill formula or event deduplication. A single terminal-empty
  response may use 0 or 1 for either page count or page identity, with zero rows and both
  flags false. This compatibility policy is not a provider promise about empty responses.
  Missing evidence is unavailable; incomplete pagination or overflow is an invalid report,
  not partial money. A complete positive-duration empty report is known zero.
- Raw event-page strings preserve decimal number lexemes. Rust checked-adds decimal cents
  per calendar period, including exponent notation, and rounds each total once, half away
  from zero, into checked integer USD cents. It never falls back to billing-cycle money.
- Ceilings are local advisory limits. Existing Cursor Month ceilings retain their exact
  stored value, now compared with extra-paid UTC calendar Month instead of the old
  cycle/included comparison basis. A missing limit differs from a present unusable zero;
  a percentage needs complete spend and a positive same-currency limit. Supported unavailable
  periods and saved selections remain visible/removable. Only Cursor-platform persistence
  uses the private `cursor-extra-paid-calendar-v1` basis wrapper: old unmarked/incompatible
  snapshots are misses without clearing, restamping or retiring credentials. New-basis
  stale fallback retains original timestamps; public JSON and other caches stay unchanged.
- Daily request counts are raw usage events, not billed request units. Count only the complete
  funding family `subscriptionIncludedReqs + usageBasedReqs + apiKeyReqs`; the overlapping
  `composerRequests`, `chatRequests` and `agentRequests` breakdown is ignored. Explicit
  canonical zeros stay known zero. An incomplete funding family makes that day's count
  unknown across all rows and pages; complete counts retain saturating addition and UTC dates.
- Official team rate limit is 60 requests per minute. Cursor documents hourly aggregation
  and recommends polling at most hourly; choose an hourly refresh interval and avoid repeated
  manual refreshes. This correction changes no scheduler or retry policy and promises no
  publication deadline. Providers shows the hourly freshness note on this Admin API row only.
- Never log the key, authorization header, or raw response bodies.

Official references:

- [Cursor API overview](https://cursor.com/docs/api)
- [Team Admin API](https://cursor.com/docs/account/teams/admin-api)
- [Staff clarification of per-member and pooled spend](https://forum.cursor.com/t/admin-api-docs-missing-includedspendcents-and-new-teams-usage-metrics/162742/9)
- [Team roles, seats and invitations](https://docs.x.ai/x-subscription/team-plans)

The extra-paid calendar correction's native/API acceptance remains **Pending** until the
executed candidate is bound to its FFI/APK/install, actual paid-only pagination and period
values, retained selections/ceilings and restoration. Source, sanitized fixtures, Mock output
and stale-cache recovery are not live-provider proof. The checks below are historical evidence
for the earlier reporting implementation, not acceptance of the event-based correction.

Verified 2026-10-20: the normalization corrections passed host checks and a preserving phone
update; the selected plan allowances were checked on the phone widget, Wear Glance and watch
face after fresh sync. These checks do not establish positive Team ledger activity or which
team paid for the personal CLI test. The owner subsequently confirmed a current paid seat;
the exact tier and seat state during the earlier test were not independently verified. The
installed CLI computes team selectability locally from direct membership, billing metadata
and a positive seat count; its listed team was unselectable despite that owner report.
The live Team ledger was still empty at that check, and the earlier test's billed context
was unresolved. No publication deadline, current Free seat or billing cause was inferred.

Verified 2026-10-21: the reporting API returned 15 daily rows with one included request and
zero usage-based or API-key requests. Complete reported spend components totalled USD 0.00.
The actual phone Team Admin API history showed 15 buckets, **1 request** and a visible nonzero
bar. This verifies positive Team reporting through the Dashboard. Empty reporting on
2026-10-20 and a positive result on 2026-10-21 do not establish the exact delay, its cause or
which earlier request produced the entry. Legacy-team identity, billing attribution and CLI
team-selection support questions remain separate and unresolved by this check.
