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
  platform-secure storage under immutable per-connection generation/revision keys. Legacy
  fixed-key installs migrate without requiring another login.
- Saved credentials are never displayed in full. Credential entry may reveal only the current unsaved value after an explicit user action.
- Optional user-defined labels for API-key connections are plain phone-local display metadata. They are stored beside the credential reference, never concatenated into the secret value, and never sent to Wear OS.
- Credentials are never sent to a WardPulse cloud service in the MVP.
- Wear OS surfaces receive dashboard summaries, not provider credentials.
- Android encrypted credential data is excluded from backup because its key is device-bound.

## Connection Storage And Recovery

`ConnectionCacheEngine` keeps lifecycle metadata and canonical normalized connection snapshots
in private Android SharedPreferences. This store contains no credentials, authorization
headers, prompts or raw reports. It includes non-secret identity digests and exact encrypted
storage key references; neither digests nor private account data are logged. Android app backup
is disabled for both credential and snapshot data.

Credential changes commit a generation barrier and discard the matching cache before awaiting
secure-storage writes/deletes. Immutable key references keep abandoned older SDK operations
from clobbering a newer login. Cancelled reconnect restores the prior immutable credential
under a fresh generation; first-time cancellation stays unconnected. Pending/unknown operations
fail closed. Explicit reconnect can recover them without selecting an uncertain candidate.
Migration backups are eligible only for the exact migrated slot, generation and token revision,
with a matching securely read identity; ordinary OAuth refresh, replacement and deletion retire
them. Snapshot corruption never changes the active credential pointer.

Secure-storage operations share a native lease queue across engines. OAuth network work has
separate ephemeral exclusion, so an explicit disconnect can commit while a fetch is pending.
A failed old-token request cannot remove a newer token revision or login. Exact retired-key
cleanup references persist until deletion is acknowledged; Claude's old pasted-token cleanup
uses this queue without rotating the active OAuth connection. Detached SDK write candidates
remain unselectable and are conservatively excluded from cleanup until process restart.

Snapshots retain their original success times. Cold recovery checks credential presence and
identity, rejects malformed/foreign/mock records, and does not manufacture unknown accounts or
zero usage. Snapshot I/O failure permits a fresh live result; credential barrier failure reports
failure before secret mutation. All connection leases are validated together immediately before
foreground/headless publication. This protects concurrent Flutter engines in one Android
process and restart; it does not promise cross-process locking or atomic network delivery
against a later disconnect.

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
  IdP hosts. The six exact HTTPS identities listed in [Cursor plan reporting](PROVIDER_NOTES.md#cursor-plan-reporting)
  permit navigation only, never cookie reads. Google authorization transitions are rejected
  by navigation policy and an Android WebViewClient request guard, including subframe and
  resource requests that Flutter's navigation delegate does not expose. Harmless CAPTCHA
  resources remain allowed. The native guard also enforces approved HTTPS main-frame hosts
  during request interception, so POST cannot bypass navigation policy. Internal `about:blank`
  loads require explicit retirement mode. Guard attachment must succeed before any sign-in
  page loads; its channel carries only view/client IDs and fixed failure categories.
  Main-document HTTP failures fail the attempt, while optional subresource errors do not. The WebView keeps its default
  user agent. After sign-in,
  WardPulse reads `WorkosCursorSessionToken` only from HTTPS `cursor.com` apex/subdomains,
  stores it in platform-secure storage, and wipes the WebView cookie jar
  (clear + verify, also on disconnect and before each new sign-in). If a wipe cannot confirm the
  session cookie is gone, Sign in refuses to proceed and disconnect warns the user. Providers
  Help explains same-account email when offered, Cancel/reopen and Advanced paste; the guide
  preserves Chrome, Firefox and Safari cookie instructions. Retry verifies a fresh wipe.
  Retired attempts cannot complete or clear a newer attempt: pending platform work and confirmed
  document retirement to a local blank page retain the shared cookie-jar lease. Unconfirmed
  retirement leaves subsequent sign-in fail-closed. Failed blank-page requests can be retried
  on Retry or Cancel/reopen without releasing the old browser early; Cancel and manual recovery
  stay available. Sticky native failures are rechecked before accepting a captured credential.
  Failed/cancelled reconnect preserves the prior secret.
- This is a dashboard session compatibility login. Reviewed official documentation does not
  establish an equivalent grant for this integration’s personal plan meters. Do not label it
  OAuth in UI or docs. SDK User API keys and Team reporting are separate.
- The phone sends authenticated read-only requests only to `GET /api/usage-summary` with that
  cookie. Session values are never logged, sent to Wear OS, or passed across the Rust FFI
  boundary. Diagnostics exclude auth query/fragment, identity/password, cookies/headers and
  raw bodies; recovery messages use fixed stage categories. Explicit disconnect deletes the local secret.
- Treat the adapter as experimental, keep failures isolated, and do not extend it to prompts,
  agent execution, or arbitrary Cursor dashboard scraping.

## Phone-to-Watch Sync

- The Data Layer payload follows `schemas/watch_dashboard_summary.schema.json`, which owns its
  version number, and contains only derived ring metrics, optional compact remaining-credits
  glance (`creditsGlance`), budget, selected allowance, provider-status, alert, freshness, and
  phone-owned manual-refresh allowance fields (`manualRefreshAllowed` /
  `manualRefreshAvailableAt`, driven by the PollCadence hard floor). Ring entries and credits
  glance carry labels and counts — never credentials, account identifiers, raw provider
  payloads, or LLM token totals.
- Mock payloads are produced only by debug builds after the user explicitly enables mock data.
  Debug Mock data is a seeded multi-provider demo (OpenAI, Codex, Claude, Cursor), not the
  legacy single `provider: mock` golden fixture. Release Wear builds reject mock payloads.
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

The private N1/N2 producer diagnostic exception is explicitly debug-only and default-off through
`wardpulseN1PairDiagnostics` in both Wear and legacy-face Gradle owners. `N1PairDiagnostics`
in `WatchSummaryComplications.kt` admits only synthetic schema9/mock, ordinal0: the singleton
`allowance.codex.plan` / `allowance.codex.spark` pair (`N1_PAIR`), both used63, or exactly two
ordered bands, an ordinary `allowance.codex.plan` followed by the
`allowance.cursor.cursor-plan-models` / `allowance.cursor.cursor-plan-other` pair
(`N2_PLAN_PAIR`), all three used63. All admitted pools are OK and plan money fields are null.
Unrelated shapes are rejected before returned-field inspection. The cases share at most four
records per process exposing fixed case/stage labels, bounded actual routing and returned
VALUE/MIN/MAX, and closed returned-type/value-type/TITLE/ramp categories, including actual
single-color Spark and Cursor-cyan ramps. Observation uses the same returned object after
the existing single load and selection; TITLE or logging failure cannot change the return.
Unexpected literals and unavailable stages remain categorized or unknown. This exception
permits no labels, request IDs, exception text, notification keys, credentials, opaque
identifiers, serialized summaries or private originals; it does not authorize ordinary summary logging.

The diagnostic legacy face uses only a generated build-directory overlay; canonical and Push
resources stay unchanged, normal builds ignore stale overlays and release diagnostic requests
fail. Its slot106 consumer can display bounded fields regardless of admission, so Root must
establish sanitized input and quiet writers before exposing it. Captures stay private, outside
public guidance and screenshot assets. Root restores normal artifacts before restoring private
original data and retires diagnostic controls. See
[private N1 pair diagnostics](../../apps/watchface_wff/README.md#private-n1-pair-diagnostics)
for stage attribution and cleanup ownership. Diagnostics establish neither repair nor causality.

## Notification Rules

A notification is read off a locked screen, by whoever is holding the phone. It may carry only
what the reader needs to act: the provider family and the window's own name. It must not carry
credentials, account identifiers, spend, or any raw provider field. Private identifiers serve
only local bookkeeping and addressing; they never appear in notification text.

The phone has independent **Alert notifications** and **Plan recovery** delivery controls.
Both default on when unset and preserve a saved Off. Threshold rules remain opt-in on Providers;
only Rust's configured-threshold observations qualify for alert delivery. Provider errors and
status severity alone never create notifications. Startup, polling and the default choice do
not request permission. An explicit foreground Off→On action may ask Android; denial preserves
the saved choice. A failed preference read cannot authorize posting or persist a fallback.

Alert posts use `wardpulse.alerts`, a fixed numeric ID and a SHA-256 tag over the structural
condition key. This opaque digest addresses notifications; it does not decide eligibility.
Recovery posts retain their separate channel and untagged IDs. No account identifier, spend,
raw error or provider payload is included in notification text or payload extras. Lock-screen
visibility still depends on Android and the user's notification settings.

Consumed alert markers and delivery choices stay in phone-secure storage. A crossing is consumed
before a post attempt; only a positively observed clear rearms it. Unknown, missing and disabled
observations retain history. Rule edits preserve identity: a clear result rearms, a still-crossed
result does not replay. Muted or denied crossings are consumed without backlog. A failed marker
read/write suppresses that condition's post and can be retried on a later accepted observation;
after a successful claim, plugin failure or a crash can lose delivery until clear. One isolate
serializes its work, but secure storage supplies no cross-isolate atomic claim: overlapping
workers can duplicate attempts or race bookkeeping. This is best effort, not exactly-once
delivery. Mock data neither posts synthetic alerts nor changes production consumed markers.

Both switches affect delivery only. Dashboard/Wear alerts, status, watch/widget publication,
recovery tracking and reset-wake scheduling remain independent. Recovery preference failures
mute posting while retaining tracking and wake work. Foreground callers recheck their current
delivery choices after repository validation. Alert choice gates posting only; recovery samples
it when entering tracking/delivery work. These checks do not make later awaits, storage or
plugin delivery atomic. The Wear app adds no dispatcher; Android may bridge phone notifications,
without a delivery or mirroring guarantee.

## Rust Core Rule

Rust may normalize raw provider response bodies, but it does not own credential storage, platform auth flows, background sync loops, or billing.
