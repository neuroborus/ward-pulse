# Security Model

WardPulse is local-first. The MVP must not introduce a custom cloud path for provider credentials or raw provider data.

## Credential Rules

- Provider credentials stay on the phone that owns the provider transport. OpenAI Platform keys
  are entered on the phone; ChatGPT/Codex sign-in uses OpenAI's device-code flow.
- Phone-held API keys and Codex OAuth tokens are stored with platform-secure storage.
- Saved credentials are never displayed in full. Credential entry may reveal only the current unsaved value after an explicit user action.
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

## Phone-to-Watch Sync

- The version 2 Data Layer payload follows `schemas/watch_dashboard_summary.schema.json` and
  contains only derived budget, selected allowance, provider-status, alert, and freshness fields.
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
