# Security Model

WardPulse is local-first. The MVP must not introduce a custom cloud path for provider credentials or raw provider data.

## Credential Rules

- Provider credentials stay on the phone that owns the provider transport. OpenAI, Anthropic, and
  Cursor platform Admin API keys are entered on the phone; ChatGPT/Codex sign-in uses OpenAI's
  device-code flow. Claude subscription uses Claude Code's PKCE authorization-code flow (browser
  plus pasted callback code); Cursor plan uses an experimental in-app WebView dashboard sign-in
  that captures the `WorkosCursorSessionToken` cookie (optional Advanced paste remains for
  recovery). This is not OAuth.
- Phone-held API keys, Codex/Claude OAuth tokens, and Cursor plan session tokens are stored with
  platform-secure storage, keyed per connection so one provider's credential never overwrites
  another's.
- Saved credentials are never displayed in full. Credential entry may reveal only the current unsaved value after an explicit user action.
- Optional user-defined labels for API-key connections are plain phone-local display metadata. They are stored beside the credential reference, never concatenated into the secret value, and never sent to Wear OS.
- Credentials are never sent to a WardPulse cloud service in the MVP.
- Wear OS surfaces receive dashboard summaries, not provider credentials.
- Android encrypted credential data is excluded from backup because its key is device-bound.

## Codex Account

- The phone shows OpenAI's device-code page in the external browser and polls only the matching
  sign-in endpoints. The one-time code expires after 15 minutes and polling stops when the user
  cancels.
- Access and rotating refresh tokens stay in platform-secure storage. They are never displayed,
  logged, sent to Wear OS, or passed across the Rust FFI boundary.
- Token refresh and session writes are serialized. A rotated session is stored before any
  subsequent reporting request so an unrelated provider failure cannot discard it.
- The phone sends authenticated read-only requests only for Codex rate limits and account token
  activity. It keeps the latest 31 daily buckets and discards profile identity fields before the
  sanitized report reaches Rust.
- A `401` triggers one token refresh and retry. Only an invalid, expired, reused, or revoked refresh
  token removes the local session; permission and transient failures preserve it. Explicit
  disconnect removes the session locally before best-effort remote revocation.
- The direct Codex compatibility endpoints are not a published third-party API. Treat this adapter
  as experimental, keep failures isolated, and do not extend it to prompts, conversations, model
  execution, or arbitrary ChatGPT backend access.

## Claude Account

- The phone opens Claude Code's PKCE authorize URL in the external browser. After approval, the
  user pastes the short-lived authorization code (`CODE#STATE`) from Anthropic's callback page;
  the phone exchanges it for tokens. Anthropic does not offer a device-code grant for this client.
- Access and rotating refresh tokens stay in platform-secure storage. Authorization codes and
  tokens are never logged, sent to Wear OS, or passed across the Rust FFI boundary.
- Token refresh and session writes are serialized. Anthropic rotates refresh tokens; the phone
  stores the new refresh token before the next reporting request.
- The phone sends authenticated read-only requests only to `GET /api/oauth/usage`. Explicit
  disconnect removes the local session.
- This Claude Code OAuth contract is undocumented. Treat the adapter as experimental, keep
  failures isolated, and do not extend it to prompts, conversations, or model execution.

## Cursor Plan Account

- The phone opens Cursor’s dashboard in an in-app WebView restricted to Cursor and known login
  IdP hosts. After the user signs in, WardPulse reads the `WorkosCursorSessionToken` cookie only
  from `cursor.com`, stores it in platform-secure storage, and wipes the WebView cookie jar
  (clear + verify, also on disconnect and before each new sign-in). If a wipe cannot confirm the
  session cookie is gone, Sign in refuses to proceed and disconnect warns the user. Settings help
  explains the flow; Advanced paste accepts the same cookie value without DevTools on another
  device.
- This is a dashboard session compatibility login, not a published Cursor OAuth grant. Do not
  label it OAuth in UI or docs.
- The phone sends authenticated read-only requests only to `GET /api/usage-summary` with that
  cookie. Session values are never logged, sent to Wear OS, or passed across the Rust FFI
  boundary. Explicit disconnect deletes the local secret.
- Treat the adapter as experimental, keep failures isolated, and do not extend it to prompts,
  agent execution, or arbitrary Cursor dashboard scraping.

## Phone-to-Watch Sync

- The version 7 Data Layer payload follows `schemas/watch_dashboard_summary.schema.json` and
  contains only derived ring metrics, optional compact remaining-credits glance
  (`creditsGlance`), budget, selected allowance, provider-status, alert, freshness, and
  phone-owned manual-refresh allowance fields (`manualRefreshAllowed` /
  `manualRefreshAvailableAt`, driven by the PollCadence hard floor). Ring entries and credits
  glance carry labels and counts —
  never credentials, account identifiers, raw provider payloads, or LLM token totals.
- Mock payloads are produced only by debug builds after the user explicitly enables mock data.
- Release Wear builds reject mock payloads.
- Account identifiers, credentials, authorization headers, prompts, and raw provider
  payloads are excluded from the watch contract.
- Google Play services restricts Data Layer data to paired apps with matching application
  IDs and signing certificates.
- Data Layer may route the derived summary through Google-owned servers when Bluetooth is
  unavailable; that cloud-routed transport is end-to-end encrypted.
- The Wear app validates the schema version and required value shapes before replacing its
  locally saved summary. Invalid payloads leave the previous summary intact.

## Logging Rules

Logs must not include:

- provider credentials;
- authorization headers;
- raw prompts;
- raw completions;
- sensitive raw provider payloads;
- full account identifiers when a masked form is enough.

Diagnostics export must redact sensitive data before writing files or sharing logs.
Provider sync diagnostics may include an endpoint label, HTTP status, provider error code,
request ID, and sanitized parser reason. They must not include response bodies or raw field
values.
Phone-to-watch logs record outcomes only and never include the serialized summary.

## Rust Core Rule

Rust may normalize raw provider response bodies, but it does not own credential storage, platform auth flows, background sync loops, or billing.
