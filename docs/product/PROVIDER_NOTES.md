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

## Consumption display

Providers may report plan allowances, purchased tokens or credits, or both. These values stay
separate from monetary budgets because their units and reset rules differ.

- Plan usage, purchased usage, and platform spend are all visible by default.
- The user may hide any surface, but at least one of the three remains enabled.
- Allowance preferences filter phone and Wear OS presentation; platform spend is
  phone-dashboard only. Preferences never discard collected data.
- WardPulse does not invent a limit, balance, or percentage when the provider omits it.
- Exact provider quantities cross shared contracts as decimal strings with an explicit `tokens`
  or `credits` unit.
- Phone dashboard allowance cards are **per account**, grouped under a provider section
  (family accent + provider name). Plan and purchased values are never summed across
  providers into one card.
- Wear / WFF strips may show remaining **purchased credits** via watch summary `creditsGlance`
  (schema v6). When `creditsGlance.provider` is set, the compact number glues onto that
  provider’s `%` strip (`% · credits`). A multi-provider aggregate (`provider` null) is for
  credits-only faces and must not glue onto a single unrelated `%` strip. LLM token totals
  stay on phone history charts — never as face `TOK` labels.

## Capability-adaptive presentation

The dashboard renders only the metrics that the currently connected providers can report. The
per-provider capability tables below are the source of truth for what each connection contributes.

- A metric no connected provider supports is hidden, not rendered as a placeholder. One row keeps a
  `?` affordance that names the connection to add and deep-links to Settings.
- `Unknown` is reserved for transient provider state: a connection that has not synced yet or whose
  last sync failed. It stays on the status indicator rather than on values.
- With no connections configured, the dashboard shows a single "Connect a provider" call to action.
- Debug **Mock data** loads a seeded multi-provider demo (OpenAI, Codex, Claude plan + platform,
  Cursor plan + platform) so the full dashboard stays reviewable without live credentials.
  Utilization reshuffles on toggle/refresh (not on automatic sync ticks); the Phase 1 single
  `provider: mock` golden remains for CLI/FFI regression only.

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

Every provider in Settings is one section with up to two homogeneous connections:

- `plan`: subscription or allowance reads (Codex device-code OAuth; Claude Code PKCE OAuth
  with authorization-code paste from the callback page; Cursor dashboard WebView sign-in that
  captures `WorkosCursorSessionToken`, with optional Advanced paste);
- `platform`: organization or team usage and cost reporting (OpenAI, Anthropic, and Cursor Admin
  API keys).

OpenAI therefore shows Codex subscription and Platform reporting together. An optional
user-defined label for platform Admin API keys is plain phone-local display metadata:

- stored beside the credential reference, never concatenated into the secure key value;
- shown in Settings and provider details in place of the generic Platform title;
- removed when the credential is removed;
- never sent to Wear OS or the watch face.

Existing stored Admin API keys remain valid after the Settings regrouping; users do not need to
re-enter them.

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
acceptance is pending.

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

Scope:

- Use an organization Admin API key (`x-api-key`) against
  `GET /v1/organizations/usage_report/messages` and `GET /v1/organizations/cost_report`.
- Request daily buckets (`bucket_width=1d`); usage also supports hourly and minute buckets.
- Usage requests `group_by[]=model` for model breakdown; cost stays ungrouped.
- Cost amounts are decimal strings in lowest currency units (cents); WardPulse rounds to integer
  USD cents after summing.
- Documented poll floor is one minute; the global slider lower bound remains five minutes.
- Never log the key, authorization header, or raw response bodies.

Revocation is performed in Anthropic organization Admin API key settings.

Official references:

- [Usage & Cost Admin API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)
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
Claude **plan** windows into one slot (`allowance.claude.plan`): the tightest remaining
non-exhausted window wins; Glance label is the short token (`5h`, `Weekly`, `Opus weekly`,
`Sonnet weekly`). Purchased `extra_usage` is not in that collapse pool and is **not** a watch
ring candidate — it stays on phone dashboard cards and can surface as a warning/error alert
when utilization crosses thresholds.

This is a compatibility integration, not a published third-party API. Endpoint or OAuth client
changes may require an app update. Never log tokens, authorization codes, or raw response bodies.

## Cursor plan reporting

Status: implemented as an experimental on-device compatibility integration on 2026-07-25;
dashboard WebView sign-in added 2026-07-26.

Cursor has no official personal-account usage API and no OAuth grant for plan meters. Settings
opens an in-app WebView to the Cursor dashboard; after sign-in the phone captures the
`WorkosCursorSessionToken` cookie (Advanced paste remains for the same value), stores it
securely, and calls `GET /api/usage-summary`, normalizing included plan pools and on-demand
meters into allowances. When the payload includes `autoPercentUsed` / `apiPercentUsed`, WardPulse
shows **Cursor Models** and **Other Models** as separate plan bars (same as the Cursor usage UI)
on the phone and as selectable watch rings. Purchased on-demand usage is phone-only (and may
alert); it is not a ring. Older combined-only payloads keep a single Plan
usage bar. Exhausted pools (`usedPercent >= 100`) are omitted from the face like other rings.
Do not claim Admin-API hourly aggregation on this experimental row. Never log the cookie or
raw response bodies.

## Cursor team Admin API

Status: implemented on 2026-07-25 for team and enterprise administrators.

Scope:

- Basic auth with a team Admin API key against `POST /teams/daily-usage-data` and
  `POST /teams/spend`.
- Spend responses use `teamMemberSpend` with `page` / `pageSize` pagination; WardPulse
  sums `overallSpendCents` across pages into the month budget only.
- Spend is billing-cycle scoped and maps only to the month budget; today and week stay
  unknown until a day-scoped spend source exists.
- Hard ceiling is 20 requests per minute; WardPulse polls at the global slider cadence (minimum
  five minutes). Usage aggregates hourly on the provider side; Settings shows that freshness
  note on this Admin API row only.
- Never log the key, authorization header, or raw response bodies.

Official references:

- [Cursor API overview](https://cursor.com/docs/api)
- [Team Admin API](https://cursor.com/docs/account/teams/admin-api)
