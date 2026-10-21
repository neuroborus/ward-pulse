# WardPulse Android — Development Plan

Updated: 2026-07-25

Product name: **WardPulse**

Short positioning:

```text
WardPulse watches the pulse of your AI tools.
```

Expanded positioning:

```text
WardPulse is a local-first dashboard for AI tool usage, spend, limits, credits, and activity across providers.
```

## 1. Goal

Build the Android ecosystem version of WardPulse: a local-first usage dashboard for AI coding and model providers.

The Android product should let a developer or small team monitor usage, cost, limits, credits, provider status, and warning signals across selected providers:

- OpenAI Platform organization reporting;
- Codex subscription usage directly from the phone;
- Claude;
- Cursor.

The first Android track is not a replacement for the physical WardPulse device. It is a software-first validation path that reuses the same product idea and later can become a companion surface for the hardware device.

The system should:

- keep provider credentials local to the user's devices;
- collect provider usage and cost data through polling where APIs allow it;
- normalize provider-specific data into one shared usage model;
- show detailed dashboards on the Android phone;
- expose a configurable Android home-screen widget for glanceable phone state (own design,
  not a copy of the watch face);
- show compact dashboards on Wear OS;
- expose a lightweight Watch Face Format watch face for glanceable state and quick app launch;
- support multiple accounts per provider;
- support user-defined budgets/limits when provider-side limits are unavailable;
- stay possible to develop fully on Ubuntu for the Android part.

---

## 2. Product shape

The Android ecosystem has four user-facing surfaces.

```text
Android phone app
   ↓
Dashboard → Watchface → Widget → Providers → Settings
(connection catalog + credentials + connection alert rules on Providers;
 systemic prefs — polling, diagnostics, legal — on Settings;
 glance layout on Watchface + Widget tabs)

Phone home-screen widget
   ↓
Configurable glanceable summary on the phone launcher (own visual language)

Wear OS app
   ↓
Compact dashboard, provider details, alerts, recent sync state

WFF watch face
   ↓
Glanceable concentric remaining rings + tap target to open the Wear OS app
```

The phone app is the primary product surface. It should feel like a compact analytics dashboard rather than a simple counter. Primary tab order:
Dashboard → Watchface → Widget → Providers → Settings.

The phone widget is a launcher glance, not a second dashboard. It should answer the same
pulse question as the watch face, with a **phone-native composition** (rectangular sizes,
system theming, optional multi-metric rows) rather than transplanting the round watch layout.
Configuration for that widget lives on the phone **Widget** tab, not in Settings.

The Wear OS app is a compressed dashboard. It should answer the question: "Is my usage normal right now, and do I need to open the phone app?"

The watch face is not the main application. It should show only the most important state and act as a fast launcher.

---

## 3. Technology direction

Chosen architecture:

```text
Core: Rust
Phone UI: Flutter
Android Wear UI: Kotlin + Compose for Wear OS
Watch face: Watch Face Format
Future iOS/watchOS/visionOS UI: Swift/SwiftUI where needed
```

This is not a single-codebase strategy. It is a shared-product-engine strategy.

The goal is:

```text
one product repository
one Rust domain core
separate platform-native UI shells
shared schemas, fixtures, tests, and release process
```

### Why this split

Rust is used for portable product logic:

- normalized usage models;
- provider response normalization;
- aggregation;
- budget and limit calculations;
- projection logic;
- alert rules;
- dashboard view models;
- deterministic tests with provider fixtures.

Flutter is used for the phone dashboard because it gives one UI codebase for Android now and iOS later.

Kotlin is used for Wear OS because Wear-specific UI, Data Layer integration, background behavior, and watch interactions are better handled through native Android tooling.

Watch Face Format is used for the watch face because modern Wear OS watch faces are declarative XML/resource packages rather than arbitrary Flutter/Kotlin-rendered UI.

Swift/SwiftUI is reserved for future Apple-native surfaces. It should not be started until the Android product model is stable.

---

## 4. Non-goals for the Android MVP

The first Android MVP should intentionally exclude:

- iOS, watchOS, and visionOS implementation;
- cloud account system;
- cloud-stored provider credentials;
- provider marketplace;
- custom provider plugins;
- arbitrary user scripts;
- real-time agent tracking unless a provider API clearly supports it;
- complex team administration;
- freemium, subscription, or in-app purchase implementation;
- Play Store production release hardening;
- pixel-perfect watch face customization.

The MVP can use mock data and one real provider adapter. The priority is to validate dashboard UX, data model, sync flow, and phone-to-watch propagation.

---

## 5. Monorepo structure

Recommended initial repository layout. The public repository name is `ward-pulse`.

Naming convention:

```text
Repository: ward-pulse
Rust crates: ward-pulse-*
Internal Rust module prefix: ward_pulse
Dart package prefix: ward_pulse
Kotlin package prefix: app.wardpulse or io.wardpulse
Android app display name: WardPulse
```

```text
ward-pulse/
  README.md
  justfile
  .gitignore
  .editorconfig

  docs/
    README.md
    DEVELOPMENT_PLAN.md
    product/
      ANDROID_GOALS.md
      PROVIDER_NOTES.md
      SECURITY_MODEL.md
      RELEASE_CHECKLIST.md

  schemas/
    dashboard_snapshot.schema.json
    provider_account.schema.json
    usage_bucket.schema.json
    budget_state.schema.json
    watch_dashboard_summary.schema.json
    plan_recovery.schema.json

  brand/
    README.md                    # brand/trademark usage rules
    icons/                       # WardPulse icons and app assets
    store/                       # Play Store screenshots, feature graphics, copy drafts
    watchface/                   # visual brand assets for watch face packaging

  core/
    Cargo.toml

    ward-pulse-core/
      Cargo.toml
      src/
        lib.rs
        model/
        dashboard/
        budget/
        alerts/
        projection/
        time.rs

    ward-pulse-providers/
      Cargo.toml
      src/
        lib.rs
        openai/
        claude/
        cursor/
        mock/

    ward-pulse-ffi/
      Cargo.toml
      src/
        lib.rs

    ward-pulse-cli/
      Cargo.toml
      src/
        main.rs

  apps/
    phone_flutter/
      pubspec.yaml
      lib/
        main.dart
        app/
        dashboard/
        providers/
        settings/
        sync/
        charts/
      android/
      ios/
      test/

    wear_android/
      settings.gradle.kts
      build.gradle.kts
      app/
        build.gradle.kts
        src/main/java/app/wardpulse/wear/...
        src/main/res/...
        src/test/java/...
        src/androidTest/java/...

    watchface_wff/
      build.gradle.kts
      src/main/AndroidManifest.xml
      src/main/res/raw/watchface.xml
      src/main/res/drawable/
      src/main/res/xml/

  bindings/
    dart/
      README.md
      pubspec.yaml
      lib/
        ward_pulse_bindings.dart
        src/

    kotlin/
      README.md
      generated/
      wrappers/

    swift/
      README.md
      generated/

  fixtures/
    providers/
      openai/
      claude/
      cursor/
      mock/

    snapshots/
      dashboard_today.json
      dashboard_week.json
      dashboard_alerts.json

  tools/
    codegen/
    validate-fixtures/
    build-android-rust/

  .github/
    workflows/
      core.yml
      phone-android.yml
      wear-android.yml
      watchface.yml
```

This tree is the initial shape and is not maintained as an inventory. The repository has since
grown beyond it (for example the `codex/` provider module, the watch summary schema and
fixture, and the `docs/site/` Vocs workspace). The repository itself and the
`project-structure` skill are authoritative for the current layout.

### Repository rules

- Keep long product requirements in `docs/product/`, not in root operational files.
- Keep the Rust core independent from Flutter, Android, and Google Play APIs.
- Keep provider fixtures sanitized. Never commit real API keys, authorization headers, raw prompts, or raw provider responses containing sensitive data.
- Generated bindings live under `bindings/`, but source-of-truth interfaces live in `core/ward-pulse-ffi`.
- The phone app, Wear OS app, and watch face must be buildable independently.
- Avoid circular ownership: platform apps consume Rust output; Rust must not depend on platform apps.
- The repository may contain brand assets, app icons, screenshots, and store graphics, but their license must be stated separately from the source code license.
- Public repository does not mean public brand rights: forks should not be allowed to publish under the WardPulse name, icon, or store identity unless explicitly permitted.

---

## 6. High-level workflow

```text
Provider APIs or mock fixtures
   ↓
Provider adapter
   ↓
Raw provider usage buckets
   ↓
Rust normalization
   ↓
ProviderUsageSnapshot
   ↓
Budget + credit + projection calculations
   ↓
DashboardSnapshot
   ↓
Phone Flutter UI
   ↓
Wear Data Layer sync
   ↓
Wear OS app + WFF complications/glance state
```

Synchronization should be pull-based by default. Usage and cost data should be treated as reporting data, not as a live event stream.

---

## 7. Core domain model

The Rust core should own stable product models. Platform-specific models can exist, but they should be derived from the Rust models.

Suggested core model:

```rust
enum ProviderKind {
    OpenAi,
    Codex,
    Claude,
    Cursor,
    Mock,
}

enum ProviderStatus {
    Ok,
    Warning,
    Error,
    RateLimited,
    AuthRequired,
    Stale,
    Unknown,
}

struct ProviderAccount {
    id: AccountId,
    provider: ProviderKind,
    display_name: String,
    workspace_name: Option<String>,
    masked_credential: Option<String>,
    enabled: bool,
    budget: Option<BudgetPolicy>,
}

struct UsageBucket {
    start_at: DateTimeUtc,
    end_at: DateTimeUtc,
    cost: Option<Money>,
    input_tokens: Option<u64>,
    output_tokens: Option<u64>,
    cached_tokens: Option<u64>,
    total_tokens: Option<u64>,
    requests: Option<u64>,
    model: Option<String>,
    project: Option<String>,
    user: Option<String>,
}

struct CreditState {
    remaining: Option<Money>,
    granted: Option<Money>,
    expires_at: Option<DateTimeUtc>,
    source: CreditSource,
}

struct AllowanceState {
    source: AllowanceSource,
    used_percent: Option<f64>,
    remaining: Option<Quantity>,
    resets_at: Option<DateTimeUtc>,
}

struct BudgetPolicy {
    daily_limit: Option<Money>,
    weekly_limit: Option<Money>,
    monthly_limit: Option<Money>,
    warn_at_percent: u8,
}

struct BudgetState {
    period: BudgetPeriod,
    spent: Option<Money>,
    limit: Option<Money>,
    remaining: Option<Money>,
    used_percent: Option<f64>,
    projected_total: Option<Money>,
    status: ProviderStatus,
}

struct ProviderSnapshot {
    account_id: AccountId,
    provider: ProviderKind,
    status: ProviderStatus,
    today: BudgetState,
    week: BudgetState,
    month: BudgetState,
    credits: Vec<CreditState>,
    allowances: Vec<AllowanceState>,
    buckets: Vec<UsageBucket>,
    model_breakdown: Vec<ModelUsage>,
    last_successful_sync_at: Option<DateTimeUtc>,
    last_error: Option<ProviderErrorSummary>,
}

struct DashboardSnapshot {
    generated_at: DateTimeUtc,
    overall_status: ProviderStatus,
    accounts: Vec<ProviderSnapshot>,
    today_total: BudgetState,
    week_total: BudgetState,
    month_total: BudgetState,
    alerts: Vec<Alert>,
    watch_summary: WatchSummary,
}
```

The exact Rust structs can change, but the direction should remain stable: provider-specific raw data enters the core, normalized dashboard snapshots leave the core.

---

## 8. Provider adapter boundaries

Provider adapters should be split into two layers.

### Platform transport layer

Owned by Flutter/Kotlin platform code:

- HTTP client;
- TLS and network policy;
- background execution;
- secure credential retrieval;
- retry scheduling trigger;
- storage of encrypted credentials.

### Rust normalization layer

Owned by Rust:

- parse provider response JSON;
- validate expected fields;
- normalize usage buckets;
- map provider-specific errors to shared error types;
- calculate dashboard-ready states.

This keeps platform-sensitive behavior outside Rust and keeps deterministic product logic inside Rust.

Recommended FFI shape:

```text
normalize_provider_response(provider, endpoint, raw_json) -> ProviderUsageDelta
merge_provider_delta(previous_snapshot, delta) -> ProviderSnapshot
build_dashboard_snapshot(provider_snapshots, settings) -> DashboardSnapshot
calculate_alerts(snapshot, settings) -> AlertList
```

Avoid sending long-running sync loops, callbacks, UI state, secure storage, or billing through FFI in the MVP.

---

## 9. Phone app scope

The Flutter phone app is the main Android product surface.

### MVP screens / primary navigation

Bottom (or equivalent primary) navigation order:

```text
Dashboard
Watchface
Widget
Providers
Settings
```

Supporting / pushed screens (not primary tabs):

```text
Provider details
Budgets & credits
Charts
Sync status / logs
About / legal
```

Do **not** add a phone primary tab for Alerts. Active alerts stay on the Dashboard; alert
**rules** live on Providers, scoped to one connection each: a plan exposes usage windows, an
organization key exposes spend against a limit the user sets. There are no global budget
rules — a threshold must never fire because a different provider spent money. Wear keeps a compact Alerts detail screen for the latest computed list only — never
rule editing on the watch.

**Watchface** and **Widget** sit between Dashboard and Providers — Watchface first, then
Widget. Surface configuration lives on those tabs, not under Settings.

- **Watchface** — configure Wear / WFF ring slots and preview the next watch payload.
- **Widget** — configure the phone home-screen widget metrics and preview (Phase 14).
- **Providers** — full connection catalog (every plan/platform row, with reporting-key
  verification and failure states), credentials / auth, **all** user alert thresholds
  (plan/purchased per connection; Today/Week/Month on platform connections), the spend limits those budget
  thresholds need — their own row entry, because a limit is a ceiling and not a rule —
  and live status for synced accounts. Threshold UI speaks **% left**.
- **Settings** — systemic only: global polling interval, diagnostics, data deletion,
  legal, debug toggles — not connections, credentials, display surface toggles, alert
  rules, glance layout, or a sixth Alerts tab.

### Home / Overview (Dashboard)

Shows:

- today / week / month spend across connections — **money only**: a limit belongs to one
  connection, so a sum of limits is a ceiling nobody set, and a percentage against it has no
  owner (per-connection percentages live on the rings and in Providers);
- additional credits if known;
- overall provider status;
- active alerts (from **user-configured** rules only; empty “No alerts” until rules fire);
- last sync time.

Example:

```text
Today
$12.40

Week
$71.30

Month
$212.10
```

### Charts

MVP chart types:

- daily spend bar chart;
- hourly or daily line chart where data exists;
- input/output token stacked chart;
- provider mix chart;
- model breakdown list;
- budget burn-down/projection line.

Charts should be useful before they are beautiful. The first implementation can use a Flutter chart package or simple custom painters.

### Providers

Providers is the **connection hub**, not a read-only status list.

It owns:

- the full connection catalog, including Not connected rows and reporting-key verification
  and failure states;
- credentials / auth entry for each connection (OAuth, session, API key — as today);
- **all user-configured** alert thresholds:
  - plan / purchased meters on plan rows (opt-in; no hard-coded cutoffs);
  - Today / Week / Month spend budgets on organization-key rows, each a user-entered
    limit plus its own threshold (providers do not report a budget). The limit is entered
    through its own row action, not through the alert dialog — it is the ceiling every
    percentage depends on, and a threshold without it can never fire;
  - UI speaks **% left**; storage and Rust keep used%;
- live status, last successful sync, last error, and supported metrics when connected.

Rules can be prepared before the first successful sync because Not connected rows stay visible.

Reporting-key feedback is implemented for OpenAI Platform reporting, Anthropic Organization
reporting and Cursor Team Admin API. Saving or replacing a key starts one existing live
load; storage alone never marks it Connected. Providers shows Checking…, Not verified or
the current reporting outcome, and Dashboard names each failed reporting connection with
matching safe feedback and an exact **Edit key** action where supported. Plan connections
remain independent. Completion survives tab changes, while label-only edits do not poll.
The durable UI rules are in
[Reporting-key feedback](product/PHONE_DASHBOARD_DESIGN.md#reporting-key-feedback).
Device, screenshot and rendered-documentation checks follow the existing Owner finalization
procedure; their receipts record acceptance separately from this implementation description.

### Settings

Settings is **systemic only** — no connection catalog, credentials, display toggles, or alerts:

- global minimum polling interval;
- local-only diagnostics export;
- data deletion;
- legal disclaimer;
- open-source license information;
- debug-only toggles (e.g. Mock data) when present.

Do **not** keep Watchface or Widget layout controls in Settings once the Watchface / Widget
tabs exist. Do **not** keep connection rows or alert rules in Settings — they live on Providers.

#### Alerts ownership (phone)

Split runtime output from configuration:

| Concern | Surface | Notes |
|---------|---------|--------|
| Active alerts | Dashboard alerts panel (and Wear Alerts detail) | Only rules the user enabled, evaluated against the latest snapshot |
| Plan / purchased alert rules | **Providers** (plan catalog rows) | One opt-in threshold per meter as **% left** |
| Today / Week / Month budget **limits** | **Providers**, its own per-connection entry | The ceiling itself, not an alert — it is what makes a percentage exist at all. Platform / organization connections only; not under Settings and not inside the alert dialog |
| Today / Week / Month budget **alert rules** | **Providers** (alert dialog) | Same remaining-% editor; a period stays disabled until that connection has a limit for it |

**Product rule:** alerts are opt-in. Provider status chrome (`Warning` / `RateLimited` from
reported utilization) must **not** invent dashboard alerts by itself. Empty “No alerts” is the
correct default until the user configures at least one rule.

Rust remains the owner of alert evaluation (`calculate_alerts(snapshot, settings)` /
`apply_alert_settings`, exposed to the phone via `ward_pulse_apply_alert_settings_result_json`)
using the persisted user rules. Platform shells persist rule preferences and render results.
Do not reintroduce automatic alerts from allowance/budget status alone.

`build_dashboard_snapshot` always emits an empty alerts list; the phone host applies stored
threshold prefs after each load (and on prefs change) before Dashboard / Wear sync.

---

## 10. Wear OS app scope

The Wear OS app is a compact dashboard, not a full settings app.

It should be built with Kotlin and Compose for Wear OS.

### Surfaces

```text
Glance       — home page: how much is left
Plan windows — second page: when each one comes back
Alerts       — reached from the Glance pill
Watch face   — utility route after Plan windows rows, also available before the first summary
```

The MVP screens (Today, Week, Providers, Last sync, and an added Usage list) were replaced in
Phase 17 by the surfaces above. Phase 13 puts configurable percent rings on the **watch face**
and makes the app home the locked text legend (`WEAR_GLANCE_DESIGN.md`) that maps face colors to
providers; the page beside it answers what the legend cannot, and its rules live in
`apps/wear_android/README.md`.

### Alerts screen

Wear-only detail for the **active** alert list from the last phone sync (not rule editing):

```text
High burn rate
Codex usage is 2.1x normal
Updated 4m ago
```

Empty list is valid: show a short “No active alerts” state. Rule configuration stays on the
phone: every threshold is connection-scoped and lives on **Providers**.

### Wear OS rules

- Do not enter provider credentials on the watch.
- Do not show long tables on the watch.
- Prefer one important metric per screen.
- Support rotary input where useful.
- Keep data readable in short glances.
- Handle stale data explicitly.
- Continue showing the last successful snapshot when sync fails.

---

## 11. Watch face scope

The watch face is a separate WFF package.

MVP watch face should show:

```text
WardPulse
Today 24%
Week 29%
OK
```

Or a more compact variant:

```text
AI 24%
W 29%
OK
```

The watch face should support tap-to-open behavior into the Wear OS app where possible.

The static today/week layout above is the accepted v1 (Phase 6). Phase 13 evolves the face
into configurable percent ring arcs driven by the phone-side ring selection.

### Watch Face Push status 2026-10-16

The implementation adds a separately signed `app.wardpulse.watchfacepush.main` APK to the
Wear build, consuming the canonical WFF resources without replacing the legacy
`app.wardpulse.watchface` package or its settings. Wear minimum API is now 33; the phone
minimum is unchanged. Supported Wear OS 6+ devices use capability-guarded Push; API 34/35
retain separate WFF installation, while API 33 runs the dashboard with face-unsupported
guidance. Local development acceptance is recorded below; production signing and Play
delivery remain separate release gates.

The **Watch face** utility keeps two home pages and the existing Alerts behavior. It offers
separate explicit install, one-time consent/use and newer-only update actions, with safe
occupied-slot guards and durable permission/activation history. See
[build/signing ownership](ANDROID_TOOLCHAIN.md#watch-face-push-builds) and the
[acceptance record](product/RELEASE_CHECKLIST.md#watch-face-push-acceptance).

For runtime Source `abebbbc5`, Runner implementation/independent review and Root Source,
artifact/device/visual review reached ZERO within local development scope on **2026-10-16**.
Final debug gates, negative release-signing guards, signed-artifact/token inspection and
cold/warm validator proof passed. Final device execution passed **16/0/0**, after the
specific old-target utility RED and final-target **2/2 GREEN**; the current JVM task was
UP-TO-DATE, with actual **96/0** belonging to UI08. Real API36 installation/consent,
N1-to-N2 customization/selection retention, API33/API34 compatibility and canonical legacy
data/editor observations passed with the recorded fallback/renderer/scroll qualifications.
Unknown occupied-slot recovery and injected loss/errors do not become real-platform proof.
Production keys, actual Play signing/delivery, physical hardware, API35 and remaining
unobserved platform cases stay open individually in the acceptance record.

The documentation reconciliation integrates
[Revision 2026-10-16 — watch-face utility entry](product/WEAR_GLANCE_DESIGN.md#revision-2026-10-16--watch-face-utility-entry),
actual canonical measurements and the approved
[500×500 fixed-dark manual-selection PNG](assets/README.md#watch-face-utility-provenance-and-wear-freshness-2026-10-16)
with the Watch guide and component guidance. The image retains its original UI08 capture
identity, bound to the unchanged final UI owner; existing screenshots and Glance geometry
are preserved. For that 2026-10-16 task, after distinct terminal approval, quiescent DONE and
Source/output ownership release, Root's required full docs build/browser/output review and
restoration of the agreed share follow the acceptance record. Actual results belong in a
separate Owner receipt and final handoff, without a second status-only Source commit.
Closure of that task requires Owner ZERO; this status makes no documentation-build
acceptance claim.

Original working inputs remain `LOCAL_ARTIFACTS/business-model/WATCH_FACE_PUSH_TASK.md`,
`LOCAL_ARTIFACTS/business-model/PLAY_RELEASE.md` sections “Автоматическая установка
циферблата” / “Совместимость и объём изменений”, and
`LOCAL_ARTIFACTS/business-model/PLAY_ROLLOUT_PLAN.md` sections 2–4. These are historical
planning references, not evidence of completed acceptance. Historical verification dates
elsewhere in this plan remain unchanged.

### Watch face rules

- Keep WFF declarative and minimal.
- Do not attempt to reproduce the full dashboard on the watch face.
- Use the Wear OS app for details.
- Use complications or supported WFF dynamic content only for simple state.
- Treat watch face state as a cached summary, not a live dashboard.

---

## 12. Phone-to-watch data flow

The phone app should be the first owner of provider sync.

```text
Phone sync worker
   ↓
DashboardSnapshot
   ↓
Persist locally on phone
   ↓
Send WatchDashboardSummary through Wear Data Layer
   ↓
Wear OS app stores latest snapshot
   ↓
Watch face reads summary/complication state
```

The Wear OS app may later support standalone mode, but this is not required for the MVP.

### MVP payload

The versioned platform transport contract is defined by
`schemas/watch_dashboard_summary.schema.json`, with a sanitized example in
`fixtures/snapshots/watch_dashboard_summary.json`. It is intentionally distinct from the
compact Rust `WatchSummary` view model. Monetary values use integer minor units and ISO
currency codes rather than presentation strings. The watch payload excludes account IDs,
credentials, prompts, and raw provider data. Version 3 adds an explicit live/mock data mode and
only the plan/purchased allowances selected by the phone display preference. Mock data is
available only in debug builds and must be enabled explicitly on the phone. The debug toggle
loads a seeded multi-provider demo dashboard (OpenAI / Codex / Claude / Cursor fixtures) that
reshuffles utilization when Mock data is toggled or the phone refreshes (automatic sync keeps the
current scenario); the Phase 1 single `mock` provider golden remains for
CLI and FFI regression only. Phase 13 plans
schema version 4, which replaces the preference-filtered allowance list with explicitly
selected ring entries. A split band has its own sanitized example,
`fixtures/snapshots/watch_dashboard_summary_paired.json`: the phone asserts its whole payload
against that file and Wear parses the same file, so a renamed key cannot pass both sides.

---

## 13. Credentials and security

The Android product should preserve the local-first credential principle.

### Credential rules

- Provider credentials are entered on the phone only.
- Credentials are stored using platform-secure storage.
- Credentials are never sent to a custom WardPulse cloud in the MVP.
- Credentials are never displayed in full after saving.
- Logs must not include credentials, authorization headers, raw prompts, raw responses, or full provider payloads.
- Diagnostics export must redact sensitive data.

### Rust core rule

Rust may receive raw provider response bodies for normalization, but it should not own credential storage or platform auth flows.

### Provider credential policy

Each provider integration must document:

- required credential type;
- required permissions;
- whether analytics/read-only credentials exist;
- whether the credential can initiate billable actions;
- how to revoke access;
- whether provider-side spending limits are available.

When provider-side limits are unavailable, WardPulse should support user-defined local budgets.

---

## 14. Polling and sync strategy

MVP sync behavior:

```text
for each enabled provider account:
  check effective polling interval
  read credential from secure storage
  fetch usage/cost endpoints
  normalize provider response through Rust
  merge into local snapshot
  rebuild dashboard snapshot
  persist latest successful snapshot
  send watch summary
  write redacted sync log
```

Effective polling interval:

```text
effective_interval = max(user_setting, provider_minimum)
```

The user setting is one global refresh interval rendered as a slider from 5 to 60 minutes
(see "Provider polling constants" below), with 5, 15, 30, and 60 minutes as natural detents.

A 1-minute cadence can exist only for mock/dev builds or providers whose documented contract
explicitly tolerates it.

### Rate limit handling

The sync layer should support:

- per-provider throttling;
- exponential backoff;
- jitter;
- `Retry-After` handling where available;
- automatic slowdown after repeated 429 responses;
- visible stale/rate-limited states in the UI.

The dashboard must keep showing the previous successful snapshot when a sync fails.

### Provider polling constants

Per-provider minimum polling intervals must live in `core/ward-pulse-providers` as named
constants, one per connection kind, each preceded by a comment linking the documentation or
observed contract the value is based on. Two kinds of values are kept apart:

- hard limits: documented request-rate ceilings (for example the Cursor Admin API allows
  20 requests per minute);
- freshness guidance: how often new data can actually appear (for example Cursor aggregates
  usage data hourly, so polling faster may keep returning the same values).

Reporting/administration endpoints are rate-limited independently from model inference and
agent traffic. Polling usage reports does not consume agent capacity and cannot slow down a
running agent; the constants must state this in their comments so the boundary stays explicit.

The app exposes one global refresh interval as a slider. Its lower bound is the strictest
hard minimum across supported connections, rounded up; its upper bound is 60 minutes.
Undocumented contracts get conservative floors rather than optimistic ones. The per-provider
clamp `effective_interval = max(user_setting, provider_minimum)` still applies. Freshness
guidance does not clamp the cadence; it is surfaced as a visible note on the affected
connection rows on Providers instead.

Detailed constants and their sources are defined in Phase 11.

---

## 15. Provider integration plan

### Phase 1: mock provider

Create a mock provider with deterministic fixtures.

Purpose:

- build UI without waiting for provider API work;
- test charts;
- test budget calculations;
- test phone-to-watch data flow;
- test watch face summary states.

### Phase 2: one real provider

Add one real provider first. Prefer the provider with the clearest usage/cost reporting API at implementation time.

Recommended order:

```text
1. OpenAI Platform organization reporting
2. Codex subscription reporting directly from the phone
3. Claude
4. Cursor
```

The exact order can change based on API access, account type, and available reporting endpoints.

### Phase 3: provider capability matrix

Each provider should have a capability descriptor:

```rust
struct BucketCapabilities {
    daily: bool,
    hourly: bool,
}

struct ProviderCapabilities {
    supports_cost: bool,
    supports_tokens: bool,
    supports_requests: bool,
    supports_credits: bool,
    usage_buckets: BucketCapabilities,
    cost_buckets: BucketCapabilities,
    supports_usage_model_breakdown: bool,
    supports_cost_model_breakdown: bool,
    supports_workspace_breakdown: bool,
    supports_active_agents: bool,
}
```

The UI should hide or downgrade unavailable metrics instead of showing broken placeholders.

### Provider connection model (research, 2026-07-24)

Every supported provider decomposes into the same two connection kinds, so provider setup and
presentation should be homogeneous:

- `plan`: a per-user subscription/allowance read (plan windows in percent, purchased tokens or
  credits), authenticated with a user-level OAuth token or session;
- `platform`: organization/team usage and cost reporting, authenticated with a
  provider-appropriate key that has reporting access.

One authorization per connection kind is unavoidable: for every provider the subscription data
and the organization reporting live behind different credentials and different endpoints. A
single provider section on Providers groups both connections; neither implies the other.

```text
Provider   Plan connection                          Platform connection
OpenAI     Codex device-code OAuth                  Admin API key
           /backend-api/wham/usage                  /v1/organization/usage/completions
           (compatibility, implemented)             /v1/organization/costs
                                                    (official, implemented)

Anthropic  Claude subscription OAuth                Reporting API key
           GET /api/oauth/usage                     /v1/organizations/usage_report/messages
           utilization % per window + extra usage   /v1/organizations/cost_report
           (undocumented compatibility)             (official)

Cursor     Dashboard session endpoints              Team/org Admin API key
           GET /api/usage-summary                   POST /teams/daily-usage-data
           plan/on-demand percentages               (official, requires reporting access)
           (undocumented compatibility)
```

Key findings per provider:

- Anthropic's official Usage & Cost API returns token usage (1m/1h/1d buckets) and daily
  USD cost as decimal strings and is documented to support polling once per minute. It
  accepts credentials with the required organization reporting rights; personal/service
  keys must not be workspace-scoped. The Claude subscription endpoint
  `GET /api/oauth/usage` is the same undocumented contract Claude Code's `/usage` command uses:
  it returns `five_hour`, `seven_day`, and per-model window utilization percentages with reset
  timestamps plus an `extra_usage` purchased-credit block, and requires the Claude Code OAuth
  token, the `anthropic-beta: oauth-2025-04-20` header, and a Claude Code user agent. Community
  monitors observe stable behavior at roughly 3-minute polling. This is a Codex-style
  compatibility integration and must degrade gracefully.
- WardPulse reads Cursor personal-plan usage through cookie-authenticated dashboard
  endpoints (`GET /api/usage-summary` and related POST
  endpoints), which report plan and on-demand usage as percentages of the billing cycle. The
  official Admin API requires team reporting access, uses Basic auth with a team API key,
  allows 20 requests per minute, aggregates data hourly, and documents polling at
  most once per hour. A Cursor plan connection is therefore the riskiest compatibility
  integration and needs explicit experimental framing.
- Codex-style plan data is percentage-first. All three plan connections can report usage as a
  percentage of a window or cycle, which is what compact surfaces (watch rings, summary cards)
  should standardize on.

Everything normalizes into the existing core model: plan windows and purchased balances map to
`AllowanceState`, platform reporting maps to `UsageBucket`/cost totals, and each connection gets
its own capability descriptor so the UI can adapt.

Credential eligibility was checked against official documentation on 2026-10-16. OpenAI
still requires an organization Admin key. Anthropic accepts qualifying reporting credentials;
Cursor's official API and Teams pricing pages give conflicting entitlement descriptions.
Provider-specific access requirements and source qualifications live in
[Provider notes](product/PROVIDER_NOTES.md#connection-grouping).

Official references:

- [Anthropic Usage & Cost Admin API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)
- [Anthropic usage report reference](https://platform.claude.com/docs/en/api/admin/usage_report/retrieve_messages)
- [Anthropic cost report reference](https://platform.claude.com/docs/en/api/admin/cost_report/retrieve)
- [Cursor API overview and rate limits](https://cursor.com/docs/api)
- [Cursor team Admin API](https://cursor.com/docs/account/teams/admin-api)

---

## 16. Active agents

Active agent tracking is a future feature.

The MVP should not depend on live agent visibility because provider APIs may expose only reporting data, not live execution state.

Future options:

- use provider APIs where available;
- support provider-specific agent status adapters;
- integrate with local CLI wrappers;
- read local telemetry where the user explicitly enables it;
- support OpenTelemetry-style ingestion for tools that emit it.

MVP UI can reserve an empty section:

```text
Active agents
Not available for this provider
```

---

## 17. Branding and provider names

The app brand should be independent.

Good names:

```text
WardPulse
TokenScope
Usage Meter
Dev Usage Meter
```

Avoid app names that look official or imply affiliation:

```text
Codex Meter
Claude Cursor Dashboard
Official OpenAI Usage Watch
```

Provider and product names such as Codex, Claude, and Cursor can be used descriptively as integration labels, for example:

```text
Connect Codex
Connect Claude
Connect Cursor
```

The app store listing and About screen should include a clear disclaimer:

```text
WardPulse is an independent usage monitor. It is not affiliated with, endorsed by, or sponsored by OpenAI, Anthropic, Cursor, Google, or any other provider. Product names are trademarks of their respective owners.
```

---

## 18. Open-source, licensing, and paid distribution

The repository is expected to be public, but the product direction is paid-first.

WardPulse should not start as a freemium or subscription-first product. Freemium, subscriptions, trials, and in-app purchases add product, billing, support, analytics, entitlement, and policy complexity. They can be revisited later, but the baseline Android application should be a paid Google Play product.

Recommended model:

```text
Repository: public
Source code: open source
Source license: Apache-2.0
Brand/assets: not open source by default
Google Play build: paid app
Freemium: not planned for the first release
Subscription: not planned for the first release
Self-build: allowed under Apache-2.0
```

### Source code license

The source license is Apache-2.0. It applies to source code, documentation,
schemas, fixtures, and tooling unless another file or directory states
otherwise.

### Brand and asset license

Brand assets are not open source by default. This includes, unless explicitly stated otherwise:

- WardPulse name;
- logo;
- app icon;
- watch face visual identity;
- store screenshots;
- feature graphics;
- marketing copy;
- any visual assets that define the product identity.

These assets may still live in the public repository. They do not need to be moved to a private repository only because the code is open source. The important rule is that their usage rights must be separated from the source code license.

Recommended position:

```text
Keep brand assets in the same public monorepo when it improves development and release workflow.
Do not rely on repository privacy to protect the brand.
Protect the brand through explicit licensing, trademark notes, and store-publishing rules.
```

Reason:

- app icons, watch face assets, screenshots, and store graphics are part of the product build/release workflow;
- keeping them near the code makes Android, Wear OS, and Play Store packaging easier to reproduce;
- a public repository can still say that source code is open source while brand identity is not;
- forks should be able to build the software according to the source license, but should not be able to publish confusingly similar WardPulse-branded products.

Recommended repository convention:

```text
LICENSE                       # Apache-2.0 source license
TRADEMARKS.md                 # WardPulse name/logo/store identity rules
THIRD_PARTY_NOTICES.md         # third-party licenses and attributions
brand/README.md               # brand asset usage notes
brand/icons/                  # app icons and visual assets
brand/store/                  # Play Store graphics and copy drafts
```

Default rule:

```text
You may study, build, and modify the source code under Apache-2.0.
You may not publish an app, fork, store listing, website, or package using the WardPulse name, logo, icon, or confusingly similar branding without explicit permission.
```

This allows the project to remain public and open while keeping the commercial product identity protected.

### Commercial distribution

A public source repository does not prevent selling the Android app through Google Play.

The paid Play Store build should be positioned as:

```text
Official signed WardPulse build
Google Play installation and updates
Convenient Android/Wear OS packaging
No separate subscription required for the base app
```

Later monetization options can be explored only if there is a strong product reason, for example:

- optional paid cloud backup;
- optional team features;
- optional hardware companion features;
- optional provider packs;
- optional premium themes/watch faces.

These are not part of the first Android MVP.

Recommended boundaries:

- keep source code license explicit;
- keep brand and assets under separate terms;
- do not allow forks to publish under the same brand;
- include third-party license notices;
- avoid bundling proprietary provider logos unless allowed;
- avoid using provider names in a way that implies official affiliation.

---

## 19. MVP implementation phases

### Phase 0 — repository foundation

Deliverables:

- monorepo skeleton;
- root README;
- this `docs/DEVELOPMENT_PLAN.md`;
- `justfile` with common commands;
- Rust workspace;
- Flutter app stub;
- Wear OS app stub;
- WFF module stub;
- fixtures folder;
- Apache-2.0 license, brand boundary, and trademark baseline;
- CI skeleton.

Useful commands:

```text
just test-core
just build-android-rust
just run-phone
just run-wear
just build-watchface
just test-all
```

### Phase 1 — Rust core with mock data

Deliverables:

- core usage models;
- budget model;
- credit model;
- alert model;
- dashboard snapshot builder;
- mock provider fixtures;
- golden snapshot tests;
- CLI command to print dashboard snapshots.

Acceptance:

```text
cargo test passes
mock fixture generates stable DashboardSnapshot
snapshot includes today/week/month budget states
snapshot includes watch summary
```

### Phase 2 — Flutter phone dashboard

Deliverables:

- Flutter Android app;
- mock dashboard home screen;
- today/week/month cards;
- budget progress;
- basic charts;
- provider list;
- provider detail screen;
- settings shell;
- local mock snapshot loading.

Acceptance:

```text
phone app starts on Android emulator
home screen renders mock dashboard
charts render stable mock history
provider detail pages are reachable
```

### Phase 3 — Rust ↔ Flutter bridge

Status: complete as of 2026-07-18.

Deliverables:

- generated Dart bindings or thin JSON-based bridge;
- Flutter wrapper for Rust core;
- dashboard snapshot generated by Rust at runtime;
- fixtures loaded through the app.

Acceptance:

```text
Flutter app calls Rust core
Rust-generated snapshot matches golden fixture
errors are mapped to UI-safe error states
```

For MVP speed, a JSON boundary is acceptable before optimizing the FFI interface.

### Phase 4 — Wear OS compact app

Status: complete as of 2026-07-18.

Deliverables:

- Kotlin Wear OS app;
- Today screen;
- Week screen;
- Providers screen;
- Alerts screen;
- local summary storage validated with sanitized fixtures;
- Compose for Wear OS UI.

Acceptance:

```text
Wear app runs on emulator
screens are readable on round and square previews
stale data state is visible
valid phone summaries are persisted locally
missing data never creates an implicit mock summary
```

### Phase 5 — phone-to-watch sync

Status: complete as of 2026-07-19.

Deliverables:

- phone app sends WatchDashboardSummary to Wear OS app;
- Wear OS app receives and persists latest summary;
- manual sync button for development;
- redacted logs for sync events.

Acceptance:

```text
changing phone snapshot updates Wear app
Wear app keeps latest successful summary offline
sync failure does not clear previous state
```

### Phase 6 — WFF watch face

Deliverables:

- WFF XML watch face;
- static WardPulse layout;
- summary slots for today/week/status where possible;
- tap target to open Wear OS app;
- ambient-friendly design.

Acceptance:

```text
watch face builds as APK/AAB
watch face installs on emulator or physical watch
tap opens WardPulse Wear app where supported
ambient mode remains readable
```

### Phase 7 — first real provider

Status: implementation complete; live acceptance pending as of 2026-07-19.

Deliverables:

- credential screen;
- secure credential storage;
- one real provider transport implementation;
- Rust normalization for that provider;
- sync logs;
- rate limit handling;
- provider capability descriptor.

Acceptance:

```text
user can add one provider account
app fetches real reporting data
dashboard shows real today/week metrics
credential is masked after save
logs are redacted
```

Completed slice:

```text
OpenAI Platform organization reporting selected as the first live adapter
provider capability descriptor added for implemented providers
usage/cost endpoint, credential, pagination, and redaction contract documented
personal ChatGPT/Codex subscription analytics kept separate from this adapter
phone credential UI stores the Admin API key in platform-secure storage and masks it after save
phone transport fetches paginated daily usage and cost reports with Retry-After/backoff handling
Rust normalizes sanitized OpenAI reports into the existing dashboard snapshot contract
sync diagnostics record outcome names only; credentials, headers, identifiers, and payloads stay out of logs
automated Rust, Flutter, FFI, fixture, pagination, retry, and credential-masking tests pass
```

Remaining acceptance:

```text
save a valid OpenAI Admin API key on the phone connection catalog (Providers tab)
  on an Android phone or emulator
refresh and confirm that OpenAI today/week/month cost plus usage/model data are rendered
confirm the saved key remains masked and no sensitive values appear in logcat
```

Codex subscription slice:

```text
phone owns Codex device-code sign-in, secure token storage, refresh, and read-only reporting
no desktop process, local server, or adb reverse dependency remains
Rust normalizes plan windows, purchased credits, and daily token buckets without fake money values
plan, purchased usage, and platform spend are visible by default; at least one surface stays on
the same filtered allowance summary is propagated to Wear OS through schema version 3
Android end-to-end acceptance remains: sign in from the Providers connection catalog
and verify the live phone/watch UI
```

### Phase 8 — MVP hardening

Status: in progress as of 2026-10-22. Manual release Stage A build automation and Stage B
verified-transfer GitHub draft publication are implemented; hosted end-to-end acceptance
remains pending. Release acceptance, real-device testing and the remaining error/offline
acceptance review remain open.
Persistent per-connection recovery is implemented and covered by host regressions and
final-APK emulator acceptance below. Phase 7 live acceptance remains a separate
provider-integration gate.

Completed slice:

- each live connection keeps its own normalized last successful snapshot in phone-private
  storage, allowing fresh foreground and headless repositories to merge fresh A with stale B;
- an all-provider failure can recover all available connected caches, while a first failure
  without cached data keeps the existing empty/error behavior;
- recovered dashboard, provider and watch-summary states are marked stale, with original
  successful-sync timestamps; a mixed snapshot uses the newest connection's generation time;
- older responses cannot replace or publish over newer connection data;
- OpenAI authentication, permission, rate-limit, availability and response failures surface as
  fixed safe messages; status icons expose concise tooltips, and credential entry can reveal
  only the current unsaved key on demand.

`ConnectionSnapshotCache` persists only the owning connection's canonical normalized data.
Credential generation, OAuth token revision and snapshot invalidation epoch are separate:
normal token refresh retains same-account snapshots, while reconnect/delete and identity
mismatch refuse obsolete data. Snapshot corruption and mock-mode changes leave credentials
intact. Publication validates all connection leases together; local load revisions also reject
superseded UI and preference callbacks. Phone, automatic and watch-requested refreshes retain
live recovery data; mock refresh still regenerates its demo and never fills the live cache.
The native transaction/lease service supports concurrent Flutter engines in the application's
single Android process and process restart, not concurrently separate OS processes.

Emulator acceptance on **2026-10-13** used the final Android x64 APK and three real plan
connections: Codex, Claude and Cursor. An actual periodic WorkManager task started a fresh
background process and Flutter engine with the launcher resumed, ran production polling,
updated all three persisted success times and delivered a watch summary. After that process
was killed, a fresh normal phone process with no active network restored the same three
snapshots as stale. A second offline read and an ignored all-unavailable entrypoint preserved
the post-worker payload hashes and original success times. The normal final APK was restored
with install-r; live polling and Wear receipt recovered, with connectivity and the canonical
watch face restored. This closes emulator acceptance for persistent restart/background
recovery, without claiming real-device hardware coverage or live acceptance for all six
connection types.

If no snapshot can be produced, `providerSyncOnce` independently attempts to mark existing
home-widget rows stale through `HomeWidgetPhoneWidgetSyncService.markExistingRowsStale`,
retaining their values and requesting a redraw. Empty/cleared widgets are left alone. This
failed-poll marker does not introduce an age-based freshness window.

A further bounded emulator UI audit on **2026-10-13** checked the reviewed phone and Wear
builds. A separate `app.wardpulse.audit` package used an independent UID and synthetic inputs;
no real credentials were imported. At 320×640 dp, font scale 1.5 and a visible keyboard, the
pasted-credential dialog scrolled Value and Label into view and kept Cancel and Save above the
keyboard, without overflow. A zero budget stayed in the dialog with validation; `25.50`
survived save/reopen, and cancelling an edit to `12` retained `25.50`. Canonical cold startup
after process death restored the three existing plan connections, and an offline refresh
retained their data as stale. Wear showed live and failed-refresh stale Glance states and all
five reported Plan windows rows. A watch-requested refresh also received a genuine phone
acknowledgement in that day's transport smoke.

Joint host gates passed 391 Flutter tests, 64 native cache assertions and 28 native widget
assertions, plus phone analysis and formatting; Wear passed 76 JVM tests with no skips, lint
and APK assembly, and 10 isolated-preferences device checks. Status complication age handling
and factual empty Alerts copy have JVM coverage and verified installed service wiring; the
aged status complication screen transition was not exercised. This is bounded emulator
acceptance, not a review of every error state, fresh authentication for all six connection
types, shipped hardware or release/internal testing acceptance. The user-guide documentation
slice was completed in Phase 21 on 2026-10-14.

Closed since this phase opened, verified against the tree on **2026-10-12**: data deletion, which
is per-connection disconnect erasing the credential from secure storage; the privacy policy, the
legal disclaimer the Settings screen carries, the Apache-2.0 source scope in `LICENSE`, the brand
boundary `docs/DESIGN_ASSETS.md` draws around `brand/`, and the paid-first distribution notes in
section 18 above. Stale data indicators are the Completed slice.

Deliverables that remain:

- error states, empty states, offline states — partly covered by the Completed slice above, not
  yet reviewed as a whole;
- **Play Store internal testing build — source, local signed RC and Play acceptance are
  separate.** The existing `just bundle-phone`, `just bundle-wear` and `just bundle-watchface`
  recipes require ignored root `key.properties` and refuse a missing host/legacy release
  key; Wear additionally requires separate Push release signing. Root owns authorized
  private setup after Runner DONE and retired ownership, first resolving whether this is
  a first publication or existing signing/uploaded-version history must be reused. Keep
  keys outside the repository and build outputs. The central
  [version table and allocation policy](product/RELEASE_CHECKLIST.md#release-versions),
  [Signing](product/RELEASE_CHECKLIST.md#signing) and
  [acceptance gates](product/RELEASE_CHECKLIST.md#acceptance-gates) own the requirements.
  Reviewed metadata and preserved guards do not prove fresh signed artifacts exist;
  inspected local artifacts do not establish Play's delivered app-signing identity or
  internal-testing installation. Record actual host artifact and Play results separately,
  leaving each unexecuted gate pending. Historical debug/emulator evidence above and in
  the [Push record](product/RELEASE_CHECKLIST.md#watch-face-push-acceptance) retains its dated
  scope, including open API35, hardware and unobserved recovery acceptance.
- real device smoke tests — every verification so far has been on emulators.

Acceptance:

```text
AAB builds successfully
internal testing release can be installed
paid-first distribution assumptions are documented
source and brand licensing boundaries are documented
no credentials appear in logs
phone and watch flows survive sync failures
```

### Phase 9 — provider-grouped connections

Status: completed as of 2026-07-24.

Rationale: Codex sign-in and the OpenAI Platform Admin key are one product relationship with
OpenAI, but Settings then presented them as two unrelated rows. Research in section 15 shows
every provider follows the same dual shape, so connections were grouped by provider (now on
the Providers tab).

Deliverables:

- one provider section per provider: OpenAI, Anthropic, Cursor;
- the OpenAI section contains both connections: Codex subscription (device-code OAuth) and
  Platform reporting (Admin API key);
- a shared connection row component: connection kind, status, masked credential,
  connect/disconnect actions;
- an optional user-defined label for API-key credentials (for example "Work org key"); the
  label is plain display metadata stored beside the masked credential reference, never inside
  the secure-storage value and never sent to the watch;
- a phone-side connection model keyed by provider kind plus connection kind (`plan` or
  `platform`), feeding the Rust `ProviderAccount.display_name` field;
- unimplemented connections (Anthropic, Cursor) appear in their provider sections as disabled
  rows labeled as not yet supported, not as hidden features;
- `docs/product/PROVIDER_NOTES.md` updated to describe the connection grouping.

Acceptance:

```text
Providers shows one OpenAI section containing the Codex and Platform rows
an Admin API key can be saved with and without a custom label
the label appears on the Providers connection row instead of the generic title
removing a credential also removes its label
existing stored credentials survive the regrouping without re-entry
```

Note (2026-07-27): the connection catalog lives on the **Providers** tab; Settings is
systemic only. The Phase 9 grouping shape (one section per provider, plan + platform rows)
is preserved.

Maintenance follow-up (2026-10-01) — completed: `211b032` made provider rows adaptive on
narrow screens by moving connection status below the subtitle while preserving the established
wide layout. `016ddbf` completed the compact case for rows with two actions by moving those
actions below the text, keeping long titles intact at 320dp without reducing the 48dp targets.
Both fixes were verified at the narrow and standard phone widths.

Maintenance clarification (2026-10-17): all six Providers connections now use the shared
`ProviderConnectionRow` hierarchy: icon, wrapping title and purpose, with existing actions
aligned right; readable status and supporting errors follow below. Alerts stays rightmost,
with reporting Budget or Cursor plan Help immediately before it. Primary and action targets
are separate and at least 48dp. The three families, plan-before-reporting order, Labels,
authentication flows, secure credential storage and current-key reporting verification are
preserved under the [Connection grouping](product/PROVIDER_NOTES.md#connection-grouping)
rules. Relevant phone connection rows, dialogs and Dashboard supporting/recovery copy use
**Codex plan**, **Claude plan**, **Cursor plan** and standalone **Plan**; contextual selector
headings, actual windows/pools and watch wire labels retain their identities. The 2026-10-01
layout measurements above remain historical evidence. Scoped phone acceptance completed at
**2026-10-17 22:21:53 UTC** for actual Runner-authored Providers changes through
`aece4cbd7f6cc3058b6bce518b9f9ea6094aa4c5`: full `just check-phone` passed with **458 Flutter
tests**; actual device checks covered all **eight Light/Dark × 360/approximately 411dp ×
font 1.0/1.3** configurations, six-row layout/actions and Root's live insufficient-rights →
working-key recovery. This accepts Providers row composition and phone Plan terminology;
Wear presentation, physical-device coverage, public captures/guidance, revised phone-to-watch
sync acceptance and unrelated app surfaces remain outside this checkpoint.

### Phase 10 — capability-adaptive dashboard

Status: completed as of 2026-07-24.

Rationale: with only one connection configured, most phone and watch metrics render as
"Unknown". The dashboard must adapt to what is actually connected and measurable instead of
filling the screen with placeholders. This phase covers the phone dashboard; the watch
surfaces get the same treatment through the ring redesign in Phase 13.

Deliverables:

- dashboard section visibility derives from connected connections plus `ProviderCapabilities`;
- budget and cost cards render only when a cost-capable platform connection exists;
- allowance cards render only when a plan-capable connection exists;
- metrics that no connected provider can report are hidden rather than rendered as `Unknown`;
- each capability-hidden section keeps a small clickable help affordance (`?` icon): tapping it
  explains which connection provides the metric and deep-links to that provider section in
  Settings;
- an empty dashboard with no connections shows a single "Connect a provider" call to action;
- `Unknown` remains only for transient states: a connected provider that has not synced yet or
  a provider that returned an error.

Acceptance:

```text
with only the OpenAI Admin key connected, plan metrics show no Unknown labels
with only Codex connected, cost and limit metrics show no Unknown labels
the ? affordance explains the missing connection and opens Settings
mock mode still renders the full dashboard
```

### Phase 11 — polling cadence constants and the global refresh slider

Status: completion was declared on 2026-07-26 from code and tests, but headless WorkManager
sync was not operational then. It was fixed by `b842e9a` and device-verified on 2026-10-04.

The July gates did not expose the defect, which was visible only in device execution: the
activity-owned `app.wardpulse/watch_sync` channel was absent from the background Flutter engine.
The resulting `MissingPluginException` was swallowed by `providerSyncOnce`'s outer catch, so the
widget update after the watch step never ran either.

Rationale: automatic polling needs explicit per-provider cadence floors before it ships.
Reporting endpoints are rate-limited separately from model inference and agent traffic, so
frequent report polling never affects a running agent; the constants must document this.

Deliverables:

- named minimum-interval constants in `core/ward-pulse-providers`, one per connection kind,
  each with a comment linking its source (see section 14);
- a `const fn` lookup in `ward-pulse-providers::poll`, the cadence counterpart of
  `provider_capabilities`, returning the minimum poll interval and freshness guidance for a
  provider connection;
- one global refresh interval setting rendered as a slider from the strictest hard minimum
  (rounded up) to 60 minutes;
- a visible freshness note on the Cursor Team Admin API Settings row explaining that Cursor
  aggregates team usage data hourly, so refreshed values may lag behind actual activity
  (not shown on the experimental Cursor plan row — that contract is unpublished);
- automatic polling on the phone, honoring the slider and the per-connection clamp; this
  absorbs the "automatic provider polling" deliverable from Phase 8. In-process
  `ProviderSyncScheduler` honors the full 5–60 minute slider while the isolate is alive.
  After process death, a WorkManager-backed Dart entrypoint runs the same sync + watch push
  at `max(slider, 15 minutes)` (Android periodic floor). Settings explains both cadences;
- the watch summary re-sent after each successful automatic sync;
- existing 429/`Retry-After`/backoff handling layered on top of the cadence.

Initial constants (round up when the contract is undocumented):

```text
Connection                    Basis                                              Floor
OpenAI platform reporting     no published per-endpoint limit; conservative       5 min
Codex subscription            unpublished compatibility contract; conservative    5 min
Anthropic platform reporting  documented to support polling once per minute       1 min
Claude subscription           undocumented; community-stable at ~3 min            5 min
Cursor plan (session)         unpublished compatibility contract; conservative    5 min
Cursor platform (Admin API)   hard 20 req/min; polled at 5 min like the rest      5 min
```

The strictest hard floor is 5 minutes, so the slider spans 5 to 60 minutes with segmented stops
  (5–15 by 1, 15–30 by 5, 30–60 by 10). Cursor’s team Admin API aggregates usage hourly on the
  provider side; instead of clamping that connection to an hourly cadence, its Settings row
  carries a visible note that refreshed values may lag. The experimental Cursor plan row does
  not reuse that claim.

Acceptance:

```text
constants exist with doc-linked comments and unit tests
the slider persists and automatic sync honors it while the app runs
headless WorkManager sync continues after process death at max(slider, 15 min);
device-verified 2026-10-04 on emulator-5556 when a background tick reached WardPulseSync and
updated HomeWidgetPreferences.xml (the emulator Data Layer AvailabilityException was unrelated
to this defect)
Settings subtitle states the open-app vs background cadence
each connection never syncs faster than its floor
a 429 response still slows the affected provider without blocking others
```

### Phase 12 — Anthropic and Cursor adapters on the connection model

Status: implemented as of 2026-07-25.

Rationale: the section 15 research shows both remaining providers fit the plan/platform split
already proven by Codex plus OpenAI Platform. Anthropic goes first because both of its
connections have stable, well-understood contracts.

Deliverables:

- Anthropic platform reporting: API-key transport with the required reporting access for
  `/v1/organizations/usage_report/messages` (historical daily buckets through UTC midnight,
  then only current-day completed minute buckets bounded by the actual snapshot end)
  and `/v1/organizations/cost_report` (daily buckets only, USD as decimal-string cents), with
  pagination, Rust daily coalescing, a capability descriptor, and sanitized fixtures. Token
  history can appear before reported costs; absent cost remains unknown, without a latency
  promise;
- Claude subscription: phone-owned Claude Code PKCE OAuth (authorize URL + pasted `CODE#STATE`),
  refresh-token storage, `GET /api/oauth/usage` normalization of window utilization percentages,
  reset timestamps, and extra-usage credits into `AllowanceState`; explicitly a compatibility
  integration that degrades gracefully like Codex;
- Cursor plan usage: session-authenticated dashboard endpoints normalized into plan and
  on-demand allowances; framed as experimental WebView dashboard sign-in (captures
  `WorkosCursorSessionToken`; Advanced paste remains), with the session token in secure storage;
- Cursor platform reporting: team API-key support for accounts with reporting access,
  with the Providers freshness note (hourly aggregation) on the Admin API row only;
  billing-cycle spend accepts canonical pooled totals or complete included-plus-on-demand
  member totals, preserving unknown data; daily counts use complete funding-channel raw
  events without adding the overlapping feature breakdown;
- capability descriptors registered for `ProviderKind::Claude` and `ProviderKind::Cursor`;
- `docs/product/PROVIDER_NOTES.md` updated per provider with credential type, permissions,
  rate limits, revocation path, and redaction rules.

Verified 2026-10-20: the Anthropic current-day and Cursor normalization corrections passed
host Rust checks (113 tests, no failures), JSON validation (23 files parsed, including schemas
and fixtures; 6 fixture files checked against schemas), Flutter
checks (472 tests, 64 native cache assertions and 28 native widget assertions), documentation
build (37 routes), both Android Rust builds, a debug APK build and preserving phone install.
Live phone history shows Anthropic 20 buckets / 39 tokens and OpenAI 20 buckets / 13 tokens.
The selected plan allowances were also checked on the phone widget, Wear Glance and watch
face after fresh sync. API budgets were not configured, so those surface checks do not claim
to display API token history. The owner subsequently confirmed a current paid Cursor seat;
the exact tier and seat state at the time of the earlier CLI test were not independently
verified. The CLI's local billing/seat metadata still makes the listed team unselectable.
The deferred live-usage item remains open for positive Cursor Team ledger activity and the
billed context of that test; the metadata discrepancy does not establish the billing cause.

Acceptance:

```text
each new connection can be added, synced, and removed from its provider section
plan percentages and purchased balances render through the existing allowance cards
sanitized fixtures cover every new parser
a failing connection leaves other providers' data visible
no tokens, cookies, or raw payloads appear in logs
```

### Phase 13 — configurable watch rings

**Selected-zero follow-up, design, injected-watch and live phone-to-watch acceptance
verified 2026-10-13.** The owner's screenshots at 11:36 and 11:38 showed Claude 5h at `0% left`
on the phone while WFF and Glance selected Weekly `23% left`. The watch now keeps the
tightest known selected percentage including zero, with deterministic window ties, an empty
grey track and only exhausted `0%` tokens in the existing dark-theme pale error red
`#FFB4AB`. Selected zero still consumes one of the three band slots and one Glance row.
Known exhausted halves retain a configured pair; unavailable halves remain absent. Budget
money labels, credits, family accents and user-configured alert rules are unchanged.
`WATCH_RING_DESIGN.md` and `WEAR_GLANCE_DESIGN.md` own the complete current contract and
the distinction between unknown, exhausted zero and a positive fraction rounded to a zero label.
The canonical round API-36 AVD at 384×384 verified Claude 5h zero, either/both paired pools
at zero, two split ordinals, all-zero rows/tracks, ambient and unchanged budget money labels
under injected captured data; all ten Wear device tests passed. A genuine refresh from an
intermediate phone APK built from the frozen zero-policy runtime updated the real Dashboard
at `12:38:04` with Claude 5h `0%` / Weekly `23%` and Codex `94%`. The received schema-9
summary (`generatedAt=2026-10-13T10:38:04.000Z`, Claude `label=5h`, `usedPercent=100`)
and both watch captures matched without injected preferences after the live sync. This
passes live zero-policy acceptance. The final persistent-cache APK and cold-worker recovery
are verified separately in the [Phase 8 completed slice](#phase-8--mvp-hardening).
No notround or hardware zero check is claimed.

Status: complete as of 2026-08-17. Every acceptance line below has something holding it, and
the walk that established this named which:

- **tests** for the payload and the Glance models — surface order, exhausted layers, and a
  deselected ring never resolving again (`watch_ring_preferences_test.dart`, which every sync
  builds its payload through), the manual-refresh window from the `PollCadence` floor and a
  pair packed into one ring (`watch_sync_service_test.dart`), the seven refresh states, credits,
  pair rows and label wording (`GlanceModelsTest.kt`);
- **generated art plus a drift gate** for the face: `watchface.xml` and its ring-type drawables
  come from `render-watchface.mjs`, and `just check-watchface` fails on drift;
- **a look on the device** for the two nobody can assert from a host: that the Glance reads as a
  legend rather than a face clone, and that ambient stays readable with rings visible.

The second kind is the weak one, and it showed: on 2026-08-17 the Glance had drifted from its own
review art by a row gap nobody's gate compares. The board set now carries the four-row ceiling
(`glance-legend-full.svg`) so the crowded case is reviewable at all.

That weak kind got its first systematic reading on **2026-10-11**: the Glance's composition
rules — band order against the face, paired-row shape and naming, the compact credit balance,
and the refresh pulse in both its cadence-cooldown and `Stale` states — were read off
`emulator-5554` against a live payload and held. Recorded under *Verified 2026-10-11* in
`docs/product/WEAR_GLANCE_DESIGN.md`, which keeps the measurements.

Rationale: watch space is limited and must never show `Unknown` filler. Plan/allowance data
across connected providers is percentage-first, so Wear and WFF standardize on concentric
percent rings. This is not “always show every provider”: the user picks up to three metrics;
plan/budget percent only — purchased meters (Extra usage, on-demand, Codex credits) are never
ring candidates (phone cards; alerts only via user thresholds);
unselected or unavailable ones simply do not render. Face visual contract:
`docs/product/WATCH_RING_DESIGN.md`. Wear **app** Glance (tile home) visual contract:
`docs/product/WEAR_GLANCE_DESIGN.md` (text legend — not a face clone). Layout ownership under each app's
`design/` per `docs/DESIGN_ASSETS.md`.

Deliverables:

- OpenPencil sources under `apps/watchface_wff/design/` and `apps/wear_android/design/` for
  1–3 concentric layers plus ambient (WFF art uses the same concentric language as Wear — not
  the old side-by-side `RING 1` / `RING 2` wireframe); one board serves both shapes, since WFF
  renders one 450-unit canvas and a square watch shows the same circle with its corners left
  to the background;
- a ring binds to exactly one metric of exactly one connection (provider **plan** window with a
  %, or that connection's local budget percent for one period — never purchased Extra usage /
  on-demand / credit meters, and never a sum across connections). One exception, added by the
  split-band revision 2026-08-13: a Cursor plan's two pools may share a single band, split
  lengthwise, and still cost one of the three ring slots the user picks (on the face they cost
  two complications, and the outer halves of all three bands share one `ComplicationSlot`);
- layer color is primarily **by provider family**, with status (warn/error) as a modulation; a
  budget ring takes its connection's family color, and a neutral grey survives only as the
  fallback for an unresolved family. The palette itself lives in `WATCH_RING_DESIGN.md`, which
  since 2026-08-13 gives the two Cursor pools colors of their own;
- **arc = remaining**: the colored sweep shrinks as the limit is consumed (not a “used”
  fill that grows toward full); melt is clockwise from 12 (usage gap advances like a
  clock hand; remaining ends at 12);
- **sort by remaining**: the tightest remaining plan limit is innermost / nearest center;
  equal plan percents break ties by credit request-runway (internal credits-per-request
  constants; UI still shows credits only). Since the 2026-10-13 selected-zero revision,
  exhausted known metrics (`usedPercent >= 100`) retain empty grey tracks and their rows;
  unavailable percentages remain omitted;
- the phone **Watchface** tab selects up to three ring slots (not Settings); metrics from
  unconnected providers stay visible but disabled with the same `?` help as the dashboard;
  purchased allowances are excluded from the ring catalog (phone cards only; alerts only when
  the user configures thresholds for those meters on Providers);
- no time-based rotation in the first iteration: simultaneous static layers are battery-safe;
- aperture: large time as hero; upper inner rim reserved for future weather; lower chord uses
  short per-family strips (`%`, remaining credits, or `% · credits`) — see `WATCH_RING_DESIGN.md`;
- remaining purchased credits on each strip for that provider family from watch `allowances`
  (same per-provider lookup as Glance; compact `% · 320` on the face); never LLM `TOK`;
- schema `creditsGlance` (v6) remains for credits-only faces (no plan rings) — not the
  per-strip credit source when plan rings exist;
- watch summary schema version 7: ordered selected ring entries (stable id, short label,
  percent, status) plus optional `creditsGlance`, phone-owned `manualRefreshAllowed` /
  `manualRefreshAvailableAt`, without credentials, account ids, or raw provider payloads;
- Wear OS **face** / WFF render concentric remaining layers; Wear **app** Glance is the legend
  screen (`WEAR_GLANCE_DESIGN.md`), not a second face;
- tap-to-open into the Wear app preserved.

Acceptance:

```text
WATCH_RING_DESIGN.md baseline locked 2026-07-25 (time hero, remaining arcs, sunk strips);
  melt/strip-accent revision 2026-07-27 (clockwise-from-12 melt; ColorRamp strip accents);
  band-width 2026-08-02; per-connection budget 2026-08-08; budget-strip 2026-08-09;
  ring-type 2026-08-11
WEAR_GLANCE_DESIGN.md baseline locked 2026-07-26 (legend rows, OK/!OK refresh, Alerts pill)
review SVGs/PNGs match those baselines (face: preview-3-plan-credits; Glance: preview-glance-legend-3)
watchface.xml and its ring-type drawables are generated (render-watchface.mjs; check-watchface fails on XML drift)
the watch payload validates against its schema (version 9 since the split band) and sanitized fixtures stay current
watch surfaces show configured known rings, including exhausted zero; unavailable metrics are omitted
Claude 5h at 0% versus Weekly at 23% selects 5h; equal known windows use established deterministic priority
selected zero has no coloured remaining arc and only its 0% token is pale error red
known paired halves retain their identities/tracks at one or both zero; all-selected-zero retains rows
tiny positive values rounding to 0% remain positive and ordinary; zero creates no new alert or refresh state
arc length = remaining; melt clockwise from 12; inner/center = tightest remaining
a budget ring's band repeats its period as cut-out type (`D` / `7D` / `M`); plan rings carry none
credits per provider family on face strips (`% · credits`) from allowances, like Glance;
  creditsGlance for credits-only faces; never LLM TOK
App Glance credits are per provider with an explicit credits label (not a footer sum)
Glance refresh: OK/!OK inside dual-arrow glyph; optional muted problem detail below plate
cadence cooldown = gray OK + disabled (no detail); provider rate limit = gray !OK + Rate limited + disabled
phone pushes manualRefreshAllowed / manualRefreshAvailableAt from PollCadence floor (not Settings slider); Wear does not invent cooldown
Stale = orange !OK + Stale + refresh enabled; Alerts: N active when N > 0, disabled at 0
metric labels use the same wording pattern across providers for the same window kind
Wear app Glance Compose matches WEAR_GLANCE_DESIGN.md (text legend — not UsageRings face clone)
disabling a provider or ring on the phone removes it after the next sync
ambient mode stays readable with rings visible
```

Landed so far:

```text
schema version 4 + sanitized watch fixture; schema v5 tokenGlance → v6 creditsGlance → v7 manual refresh flags
phone Watchface tab owns ring-slot prefs + payload preview; Settings is systemic only
Watch ring visual baseline locked (WATCH_RING_DESIGN.md + render-watch-ring-designs.mjs)
Wear Glance legend baseline locked 2026-07-26 (WEAR_GLANCE_DESIGN.md + glance-legend-* review art)
Initial phone payload omitted exhausted layers; superseded by the selected-zero follow-up of 2026-10-13
Wear Compose UsageRings: remaining arcs + sunk family strips (time stays on system/WFF)
WFF v2 concentric remaining arcs (WeightedStroke + ColorRamp) + sunk `%` / credits strips
Strip TEXT carries the full label (`100% · 500`); accents via RANGED_VALUE ColorRamp
Credits per provider family on face strips from allowances (same as Glance); creditsGlance for credits-only
Clockwise-from-12 remaining melt (Transform startAngle; review art regenerated 2026-07-27)
Wear Glance Compose text legend landed (GlanceLegendPage; watch→phone refresh request)
Ring band widened to a measured 20.2 units at a 24-unit pitch, strip stack re-spaced (2026-08-07)
Budget rings key by connection and take its family color; summed Today/Week/Month rings retired (2026-08-09)
Budget strips read spend of limit (`$12.34/100`); the aggregate budget percentage is gone (2026-08-09)
watchface.xml generated from tools/render-watchface.mjs (2026-08-10)
Budget ring bands repeat their period as baked cut-out type from generated drawables, four sweeps broken on the diagonals (2026-08-11)
A Cursor plan's two pools share one band: outer/inner halves, one complication slot for all three bands, schema v9 (2026-08-14 → 2026-08-16)
Glance shows a pair as two adjacent rows, own pool first; the face keeps it one band (2026-08-15)
Glance rows sit on the art's 54 pitch and keep 12 clear of the Alerts pill — four rows is the ceiling (2026-08-17)
```

Maintenance follow-up (2026-10-01) — completed:

- `00e75ab` made a lone pool from a former split band render as a full band again: ordinary
  rings now publish a non-split `TITLE` instead of leaving the face with stale split state;
- `cb3720f` kept a positive near-exhausted remainder visible by drawing below the two-cap cutoff
  without the cap inset; the decision and device result are recorded in the dated
  `docs/product/WATCH_RING_DESIGN.md` revision;
- `511158b` measured the three-band Glance on round and notround screens and removed the three
  layout deferrals in `docs/product/WEAR_GLANCE_DESIGN.md`. This verifies paired-row fit and
  clipping under injected load and contributes to the completed Phase 18 acceptance;
- `533e35e` recorded the decision to keep device-font clock spacing unchanged in the dated
  `docs/product/WATCH_RING_DESIGN.md` revision, including the measured alternatives and their
  costs.

The two rendering fixes were verified on the watch; the locked revisions remain the source for
their measurements rather than repeating those measurements here.


Future (not Phase 13 acceptance — product direction):

```text
Phase 13 / locked baseline: up to three Watchface ring slots (watchRingSlotCount = 3);
  purchased meters are not rings (phone cards; alerts only via user thresholds).
Later: possibly up to three profiles/accounts for the same provider on one device.
When multi-profile lands, same-provider rings need hatch/pattern as well as family color
  (keep the three-ring face cap unless a later design revision raises it).
```

### Phase 14 — Watchface / Widget tabs and phone home-screen widget

Status: largely landed (2026-07-27). Primary nav, Watchface + Widget tabs, locked
`PHONE_WIDGET_DESIGN.md` review art, and the Android App Widget surface are in tree.
Large (6-slot) prefs unlocked; launcher hugs complete rows/columns (1–6 by height;
credits→label drop by width); Claude windows stay expanded on the phone widget;
exhausted pools render as `0% left`.

Read on a launcher for the first time on **2026-10-11**, on the canonical phone AVD: the locked
composition held on every rule a home screen can show — the hug and the credits drop by width,
two-line labels, tightest-first order, day and night chrome sampled exact against
`colors_widget.xml`, the tap target, and the empty state. The last acceptance line below was
witnessed twice: placing the widget and changing the Widget tab's selection updated the surface
without a reinstall, and later the same session a provider window crossed its threshold
unprompted and the placed widget re-sorted itself to match — the data moving under it, with
nothing touched. The `STALE` overlay was not reached, because the payload was fresh. Recorded
with its measurements under *Verified on a device 2026-10-11* in
`docs/product/PHONE_WIDGET_DESIGN.md`.

The final-APK widget follow-up on **2026-10-13** reached the failed-refresh state: retained
rows carried a `STALE` badge with five physical pixels clear before the first metric row in
normal-font light mode and font-scale-1.5 dark mode after redraw. Narrowing the launcher frame
from `[67,546][1013,1449]` to `[67,546][519,1449]` exercised percent-only mode: labels and
credits hid as designed, with `STALE` ending at y=601 and the first percentage starting at
y=606. The original frame was restored. Widget taps from Settings and an open Budget dialog
opened Dashboard and cancelled the modal; after a genuine process kill, a cold tap passed
through loading to the three existing plan connections. The native fitter still estimates
each row at 31 dp. Very short widget heights and very large font scales remain separate
acceptance cases. The zero-row resize prompt versus an empty selection has JVM coverage;
its screen output was not exercised in this audit. These observations do not extend the
widget's failed-refresh marker into an age-based freshness rule.

Rationale: glance configuration is a first-class product surface, not a Settings footnote.
Watchface and Widget each get a primary tab between Dashboard and Providers. The phone
launcher also needs the same glanceable “pulse” as Wear/WFF, but a round watch composition
does not fit Android widgets — the widget gets its **own locked visual language** while
reusing the metric catalog, remaining-% semantics, family colors, and “never invent Unknown
filler” rules.

#### Navigation / IA

Primary tab order:

```text
Dashboard → Watchface → Widget → Providers → Settings
```

- **Watchface** owns Wear / WFF ring slots and payload preview (moved off Settings).
- **Widget** owns phone home-widget metric slots, payload preview, and the Android App Widget
  (`PHONE_WIDGET_DESIGN.md` locked; prefs independent of Watchface).
- **Providers** already owns the connection catalog, credentials, and connection alert
  thresholds.
- Settings stays **systemic only**: global polling interval, diagnostics, data deletion,
  legal — not connections, not credentials, not alert rules, not Watchface/Widget
  layout, and not a sixth Alerts tab.

#### Widget surface

Locked visual contract: `docs/product/PHONE_WIDGET_DESIGN.md` (review art under
`apps/phone_flutter/design/`). Do not copy `WATCH_RING_DESIGN.md` layouts into the widget.

Deliverables:

- Android App Widget hosted by the Flutter phone shell (`home_widget` + RemoteViews);
- Widget tab selects which metrics appear (same catalog idea as Watchface: provider plan
  windows, purchased/credit % when available, per-connection local budgets);
- small→tall resize shows 1–6 complete column-rows by allocated height (olive card hugs
  rows/columns; width drops credits→label→%); day/night chrome + overlay face watermark;
  prefs cap `phoneWidgetSlotCount = 6`; Claude windows stay expanded; exhausted pools as
  `0% left`; Glance-style credits end-aligned (label centered);
- render only configured, available metrics (exhausted stay as `0% left`); omit empty
  slots rather than inventing `Unknown` filler;
- **remaining** language for percent metrics (same meaning as watch rings); family colors from
  the shared palette in `WATCH_RING_DESIGN.md`, with a budget row taking its connection's family
  color;
- update after provider sync / scheduled refresh without opening the full app; cached data
  retained after a failed refresh is marked stale, with no widget age-based freshness window;
- tap opens the phone app (Dashboard);
- no credentials, account ids, or raw provider payloads on the widget surface or in widget
  logs;
- widget payload unit tests; emulator smoke for at least one size; review art in
  `apps/phone_flutter/design/`.

Acceptance:

```text
primary nav is Dashboard → Watchface → Widget → Providers → Settings
Watchface tab owns ring-slot prefs; Settings no longer hosts Watch display
Providers owns connection catalog, credentials, and connection alert thresholds
Settings is systemic only (polling, diagnostics, legal)
Widget tab owns widget prefs independently of Watchface
PHONE_WIDGET_DESIGN.md baseline locked with review art for small/medium
widget shows configured available metrics (exhausted as 0% left); hugs complete rows/columns
remaining-% / family colors match the product palette
tap opens the phone app; no credential UI on the widget
failed refresh retains existing widget data and marks it stale; no age-based window is defined
adding/removing the widget and changing prefs updates the surface without a full reinstall
```

Non-goals for this phase:

```text
interactive controls inside the widget (sliders, connect flows)
copying the concentric watch-face layout onto the phone
burying Watchface / Widget config under Settings
iOS widgets
multi-profile hatch patterns (same future note as Phase 13)
```

### Phase 15 — plan recovery notifications

Status: complete as of 2026-10-05.

Everything WardPulse itself controls is covered by tests: the edge in the Rust core, the phone's
memory of what was spent, the notification and what it may say, the wake booked from the reset
instant, and the Settings switch with its permission ask. Data Layer delivery was measured on
the local AVDs on 2026-10-06: Android Studio paired them over its ADB bridge without BLE, and
starting `app.wardpulse` on the phone produced `I/WardPulseSync: Watch summary received.` on the
watch before its complications refreshed to match the phone panel. The notification bridge that
carries a recovery to the watch was measured separately on 2026-10-08, once the companion held
notification access: a notification posted on the phone appeared on the watch, bridged by
`WearServices` rather than reposted. WardPulse's Wear app posts no notifications of its own, so
it cannot create a duplicate itself.

Rationale: an exhausted plan window is the one state the user is actively waiting to leave.
Today the product says nothing when it ends — the ring simply reappears after the next poll,
and the user learns it by opening the app they could not use. A recovery is worth an
interruption; nothing else in the product is.

**A recovery is an event, not an alert.** Alerts are user-configured thresholds that stay true
while the condition holds and are listed on the Dashboard and counted on Wear. A recovery is an
edge — `usedPercent >= 100` yesterday, usable now — that happens once, has no steady state, and
needs no rule to configure. It must not enter the alerts list, must not be counted by Wear's
`Alerts: N`, and must not bring back a phone Alerts tab.

Deliverables:

- the edge is computed in Rust from the windows the phone remembered as spent and the new
  snapshot, so the rule stays deterministic and testable and the shells stay transport-only;
- it fires only for a window that was **exhausted** — one that merely rolls over while it still
  had headroom is not news. A reset instant is not required to fire: a provider that does not
  say when a window rolls still has real recoveries, they simply arrive with the next poll
  instead of a wake booked for the instant;
- delivery is **scheduled from `AllowanceState.resets_at`**, not discovered by polling: the
  reset instant is already modeled and all three plan families fill it in — Claude, Codex and
  Cursor — while platform connections carry billing reports with no window to reset. So the
  feature is not Claude-only, and no adapter needs new data. The refresh cadence (5–60
  minutes, 5-minute floor) would make a polled notification late by up to an interval. The next
  poll confirms, and a moved window reschedules or cancels;
- notifications are **on by default** with one systemic switch in Settings (not a per-connection
  rule on Providers — there is no threshold to configure). Android 13+ still governs
  `POST_NOTIFICATIONS` at the OS level, so "on by default" means the app asks, not that it
  bypasses;
- watch delivery relies on Android's notification bridge. The Wear app does not post recovery
  notifications of its own, so WardPulse has no second notifier that could duplicate a bridged
  notification;
- plan and allowance windows only in the first iteration. A local budget rolls on the user's own
  calendar rather than a provider clock, and whether that deserves the same interruption is a
  separate question.

Decided 2026-08-16, on the three questions the deliverables left open — all three answered by
what the repository already carries:

- **the notification is posted through `flutter_local_notifications`**, revised 2026-08-17. The
  first answer was to post from the Android host over a method channel, on the grounds that a
  dependency costs more than a channel and one `notify`. That was wrong about where the code
  runs: an app-level channel is registered in `MainActivity.configureFlutterEngine`, so it
  exists only in the Activity's engine. The wake that matters here fires with the app closed, in
  the WorkManager background isolate, where `DartPluginRegistrant` registers pub plugins and
  nothing else — a channel call from there raises `MissingPluginException`. A plugin is the
  conventional way to reach the notification manager from that isolate, which is what the
  repository's "conventional and clearly justified" exception is for;
- **it is scheduled with `workmanager`**, already in the tree, as a one-off task delayed to
  `resets_at`. An exact alarm is not available in practice: `SCHEDULE_EXACT_ALARM` is granted to
  alarm and calendar apps, which this is not. Firing inside the Doze window is what "scheduled
  from the reset instant rather than discovered by polling" means here, and the poll that runs
  on waking is what confirms the recovery, reschedules a moved window, or cancels it;
- **the watch path uses Android's notification bridge**, rather than posting its own. The
  `com.google.android.wearable.notificationBridgeMode` lever belongs in the **Wear manifest**,
  beside the `standalone` key already there. WardPulse does not set it because the Wear module
  never posts a notification and therefore cannot create an app-side duplicate.

The phone must also **persist which windows were spent**: the edge needs a past, and the process
does not survive between polls. Keys, not whole snapshots — phone preferences live in
platform-secure storage beside credentials, and a few window ids belong there in a way that
kilobytes of usage data do not.

Acceptance:

```text
a window crossing exhausted → usable notifies exactly once per crossing
a window that was never exhausted notifies never
a spent window books its wake from the reset instant, never sooner than the poll floor,
  and none at all once that instant is behind and the provider still reads it spent
a reset instant that moves reschedules; a disconnected provider cancels
the recovery is absent from the Dashboard alerts list and from Wear's Alerts count
the switch is in Settings, is on by default, and survives reinstall of the widget/watch surfaces
no notification carries credentials, account ids, or raw provider payloads
```

Open question — a marker on the watch face:

```text
A filled family-colored dot above the clock would say "this one is back" without the phone.
Three things had to be settled before it could be drawn. The first was the band it would sit
in: WATCH_RING_DESIGN.md reserved the upper inner rim for a future weather glance and forbade
placeholder chrome. That reservation resolved on 2026-10-09, and not in the marker's favour:
the weather it was held for is now drawn as the face's own chrome at no slot cost, and the
band holds three cells that belong to the wearer, none of them reserved for anything of ours.
The other two are untouched: a dot needs its own data channel (a complication slot) and a
lifetime, since nothing on the face expires by itself; and one dot cannot carry two families
when two plans recover together. The weather is no precedent for the first of those — WFF
reads weather from a built-in source, while a recovery marker carries WardPulse data, and a
complication slot is the only way that reaches the face.
Until those are answered the face already says it in its own language — since the 2026-10-13
selected-zero revision, an exhausted selected ring keeps its grey track and 0% label; recovery
restores its coloured arc on the next sync. A marker lands only with a
WATCH_RING_DESIGN.md revision and a schema field to carry it.
```

Non-goals for this phase:

```text
turning a recovery into an alert rule, a threshold, or an Alerts tab entry
notifying on every window roll-over regardless of exhaustion
a server, push service, or any inbound channel — scheduling is local to the phone
desktop agent state (whether a coding agent is waiting on the user) — different sensor,
  different transport, not this phase
```

### Phase 16 — one declared order for the phone tabs

Status: completed as of 2026-08-16. Phone shells only; watch and widget **surface** order is
locked by Phase 13 and is not touched here.

Rationale: the phone answers "in what order do providers appear" three different ways today,
and one of the three was never decided by anyone. Providers renders the catalog in enum order
(`ProviderFamily { openai, anthropic, cursor }` × `ConnectionKind { plan, platform }`), which is
repository history rather than meaning. The Dashboard has no declared order at all:
`_providerDashboardSections` groups accounts into a `LinkedHashMap`, so `grouped.values` returns
insertion order — which is the order the snapshot arrived in, which is the order
`buildLiveProviderStack` chains its `connect(fallback: …)` links. Rewiring that chain for
readability silently reorders the user's main screen, and no test holds it.

The value being bought is **stability**: a dashboard opened ten times a day is fast because the
card is where it was last time. So order by keys that change rarely, and let position move only
when something real changed.

Deliverables:

- one ordering function per surface in the phone shell, declared and covered by tests — no
  surface may inherit its order from assembly or from a map's insertion order;
- composite comparators, matched to what each tab is for:

| Tab | Its job | Keys, in order |
| --- | --- | --- |
| Dashboard | watching | needs action → usage over the period → alphabetical |
| Providers | managing | connected → needs action → alphabetical |
| Watchface / Widget | picking metrics | selectable → alphabetical |

The two pickers already group before they sort: since 2026-08-16 both list their rows under a
heading per kind of limit (plan usage, platform limits) and a sub-heading per connection
(`groupMetricCatalog`). Ordering therefore has two questions to answer, not one — where a
connection sits among its peers, and where its rows sit inside it — and the second one is
already answered for budgets by the period order the catalog builds.

- **"needs action" means status**, not percentage — and it is read off the scale that already
  exists: `ProviderStatus::severity` (`Ok` 1 → `Error` 7) with its Dart mirror in
  `provider_status_severity.dart`. Sort by that rank descending; do **not** enumerate a subset
  here. A hand-written list of "the bad ones" is how the product ended up with five disagreeing
  status scales once already, and it would silently drop `Error`, the worst of them. Status
  changes weekly at most, so it can jump a row without shuffling the list;
- **"usage" means spend or volume over the period**, never the live remaining percent. Remaining
  percent crosses its neighbours on almost every poll, and a list that reshuffles itself on a
  timer destroys the muscle memory this phase exists to protect. The key needs no new data —
  `spent` per account is already in the snapshot;
- **alphabetical sorts on a stable id**, never on the displayed label, so the order cannot
  follow a copy edit or a future translation. Which id depends on what a row is: only the
  pickers list connections, and they sort on the connection id. The Dashboard and Providers
  both list families — Dashboard uses `providerFamilyOf` for one section per known family
  (retaining unclassified provider fallbacks), Providers one card per `ProviderFamily` — so
  they sort on the stable family key. **Dashboard clarification 2026-10-17:** severity covers
  its accounts and cards; admissible same-currency month spend is aggregated only for ordering,
  never as a new displayed total. Each source retains its own allowances, history and model
  detail, placed by connection/account identity independently of labels. Providers keeps plan
  above platform, which is layout rather than order. See
  [Family and source ownership](product/PHONE_DASHBOARD_DESIGN.md#family-and-source-ownership);
- **"selectable" is not "connected"**, and only the pickers have this key at all. A provider that
  is not connected has no account in the snapshot, so `watchRingCatalog` never builds a row for
  it — there is nothing to sink. What the catalogs do keep visible but disabled is a row that
  cannot be put on a ring: an allowance with no percentage, or a budget period with no limit
  set. That is the state the pickers sort on, and `WatchRingMetric.isAvailable` already names
  it. The Dashboard and Providers have no such row: the Dashboard shows no card for a provider
  outside the snapshot; represented sources without usage data retain their state, and
  Providers ranks by whether a credential is stored.

Decided 2026-08-16, and both answers are about the same thing — a list that does not move
under the reader:

- **numbers alone never reorder a surface.** A list is rebuilt when a provider changes state —
  connected, gone unavailable, or a new status — and not when a poll merely moves its figures.
  Where a key already steps only with that state, sorting delivers this on its own; where a key
  is continuous, as spend is on the Dashboard, the computed order is held for the run and
  recomputed on the next state change;
- **all four tabs take their order from this phase**, each by its own rule from the table above.
  Settings has no provider list and is not one of them.

Acceptance:

```text
every phone surface takes its order from a named function, and a test fails if the order changes
a refresh that changes only percentages or spend leaves every phone surface in the same order
a provider changing state — connected, available, status — is the only thing that reorders
the same accounts in a different order render the same Dashboard, whatever buildLiveProviderStack chains
Dashboard and Providers rank status by ProviderStatus::severity; no sixth status scale appears
equal keys are broken by the stable id — the provider key, or the connection id in a picker — and renaming a label moves nothing
Watchface / Widget catalogs list selectable metrics first and keep the unselectable ones visible but disabled
watch and widget surface order stays tightest-remaining-first (Phase 13), unaffected by this phase
```

Open question — a personal order (**skipped 2026-10-08 by the owner**):

```text
A dashboard is a personal shelf, and dragging cards into place would beat any default we pick.
It also replaces the usage key rather than joining it: a user-defined order is the answer to
"what matters to me". Worth doing after the declared order lands, not instead of it — an
explicit default is what a personal order overrides.

Skipped on 2026-10-08: the owner does not consider a user-arranged card order worth the work.
The declared order from this phase stands as the answer. Reopen only on a user request for it.
```

Non-goals for this phase:

```text
reordering the primary tabs themselves (Dashboard → Watchface → Widget → Providers → Settings)
sorting any phone surface by live remaining percent
changing watch, Glance, or widget surface order
```

### Phase 17 — the watch's second page

Status: completed as of 2026-08-17. Replaces the Today, Week, and Providers screens delivered by
Phase 4, together with the Usage and Last sync screens and the menu that led to them; Phase 4
stays as written, as the record of what the watch was before the Glance.

Rationale: the menu is a leftover from the era when the app's home was a list of summaries. The
Glance took that job in Phase 13 and answers *how much is left* better than any list — mini arcs,
per-provider credits, one Alerts pill. Of the six menu entries exactly one was still needed:
Alerts, the pill's destination. Usage and Providers repeated the Glance, the ring buttons above
them repeated its rows, and Last sync answered a question the Glance already answers with
`Stale`. Today and Week showed a currency total no design asks the watch for: the Glance carries
per-provider credits and a budget row, and a money ceiling belongs on the face's budget strip.

**The second page answers when a window comes back.** Originally, Glance omitted exhausted
windows and this was their only watch surface. The selected-zero revision of **2026-10-13**
supersedes that omission: Glance keeps a selected known exhausted window at `0% left`, while
this page still supplies its reset time and the full window inventory. The list keeps every plan
window, spent or untouched, because it doubles as the inventory of what the watch knows; a list
that changed shape with every poll would leave "not spent" indistinguishable from "not reported".

Deliverables:

- the row model is pure Kotlin with `now` as a parameter, tested the way `isStaleAt(now)` is —
  order, filtering, and every phrasing rule are unit tests, not screenshots;
- purchased meters never appear: they do not come back, they are bought again. Cursor's on-demand
  pool is the one that carries an instant at all, and it is a billing cycle turning over rather
  than capacity returning. Their home is the phone's cards;
- order is exhausted first, then soonest return; a window that cannot name a **future** moment
  sorts last inside its group. A reset already behind counts as none — the provider has not
  caught up with its own clock, and printing a passed moment would say the window is late rather
  than the number;
- the line drops whichever half cannot be said, falls back from share to bare remainder for a
  plan with no published ceiling, and reads `Unavailable` rather than rendering an empty line;
- the page draws through the existing `SummaryScreen`, so the title takes the window's own status
  color and urgency arrives for free; no new component;
- rules live in `apps/wear_android/README.md` beside their owner. `WEAR_GLANCE_DESIGN.md` scopes
  itself to the first page and only names the second in its surfaces table;
- the removal takes its orphans with it: the ring detail route, the used-percent label, and the
  last-sync formatters, each checked for callers across `main` and `test` before deletion.

Acceptance:

```text
swiping up from the Glance lands on the plan windows themselves, with no menu in between
an exhausted window is first, and a window whose reset is unpublished or behind ends its line
  after the share instead of naming a time
a window rolling today reads back at HH:MM; any other day carries its date
purchased meters are absent from the page
the Alerts pill still opens the Alerts screen, and swiping right returns to the Glance
no app screen shows a currency total; money on the watch stays on the face's budget strip
```

Non-goals for this phase:

```text
bringing a currency total back to the watch under a new name
rule editing on the watch — Alerts stays the active list only
a face marker for a recovered window (that question belongs to WATCH_RING_DESIGN.md, Phase 15)
review art for the page — the Glance generator draws a legend, not a list, and the README
  sketch carries the layout until it becomes contested
retiring the payload fields this phase orphaned (today, week, projectedTotal) — the Wear store
  still requires them, so dropping one is a schema revision, not a cleanup
```

### Phase 18 — Codex Spark as the second half of a band

**Selected-zero revision 2026-10-13.** A configured pair retains both known pool identities,
half-tracks and percentage tokens when one or both reach zero. Exhaustion no longer turns a
known pair into a lone pool or removes both; actual unavailability still does. This changes
the selected-zero acceptance of Phase 13, preserving this phase's fixed inside/outside pool
order and one-band/one-row packing.

Status: completed as of 2026-10-04.

Acceptance uses reproducible injected load because Codex no longer reports the second named
limit; the current `gpt-reserve` entry is a base-model reserve, not its substitute.

Landed in order: `26c321a` (two-limit fixture), `e13be9f` (window naming rule), `299e3f5`
(Spark colour), `7724071` (phone reads every limit), `f73e389` (a slot freed), `e6295e1`
(paired Glance row), `90bd63e` (split bands as a table), `7ae235f` (Codex paired with Spark).
Every gate passed on each.

Rationale: on 2026-08-21 Codex reported more than one limit. Beside the plan's own window sat
`GPT-5.3-Codex-Spark`, metered separately, with both a 5-hour and a weekly window of its own.
The product did not see it: `_normalizeRateLimits` hard-coded `limitId: 'codex'`, read only the
root `rate_limit`, and never looked at `additional_rate_limits`, so Spark was discarded on the
phone before Rust could normalize it. That is the shape Phase 13 already solved for Cursor's two
pools — a band split lengthwise — so the answer was to reuse the split band rather than invent a
second idiom.

The split-band mechanism is provider-independent: its table can pair any configured two pools
of one plan. The only provider-facing Spark binding is `codex_bengalfox` in
`_additionalRateLimits` (`apps/phone_flutter/lib/sync/codex_account_client.dart`); recognizing
another named limit requires one entry in that table, not a repeat of Phase 18.

**The face's slot ceiling is what made this more than an adapter change.** The eight-slot
budget was already fully spent (`WATCH_RING_DESIGN.md`, which owns the rule), and the split band
spent two of those slots on channels serving every band at once: one outer half and one far
marker, each dispatching by `TITLE`. One slot renders one complication, so only one band could
split at a time. Freeing a slot is therefore a precondition for showing Cursor's pair and
Codex's pair together, not a later optimization.

Deliverables:

- a sanitized two-limit fixture whose shape is taken from a live Pro account, where the main
  limit carries one weekly window and Spark carries both. Each record in `rateLimitsByLimitId`
  states its own `limitId`: the allowance id is built from that field rather than the map key,
  so a record that omits it silently collides with the main limit while every gate stays green;
- a window naming rule that fires only when a limit has a name *and* both windows, so the
  unnamed live Codex plan keeps the locked `Codex · Weekly plan` string byte for byte;
- Spark recognized by a table from `metered_feature` to an id of our own (`codex_bengalfox` →
  `spark`), never by the display name, which moves with every model version. An unknown feature
  is skipped rather than shown under a codename — Spark may be absent, but never wrong;
- `#186020` for Spark, clearing the palette's ΔE floor of 20 against every existing colour, with
  its branch above the family branch on both surfaces: a `spark` id starts with `allowance.codex`
  and the family branch would otherwise swallow it, losing the split with no error;
- the far marker folded into its strip's own slot, paid for by a static colour chosen from a
  closed vocabulary, which frees the slot that lets two bands split at once;
- a paired band drawn as one Glance row rather than two, so three bands stay three rows;
- per-limit collapse, so the plan's windows fold to one ring and Spark's to another before the
  two are paired, and pairing stated as a rule over pools rather than the two Cursor ids it was
  first written for;
- a recorded device spike on whether a Watch Face Format expression can read a number out of
  `TITLE`, and at what precision. Its outcome is the deliverable, either way: a negative result
  settles the question and leaves everything above working.

Acceptance — completed 2026-10-04. Injected-load device checks verified fixed half order, a lone
pool returning to a full band, and the one-row Glance pair. Regressions in
`watch_ring_preferences_test.dart`, `watch_sync_service_test.dart`, `GlanceModelsTest.kt`, and
`WatchComplicationTextTest.kt`, with `RingFamilyTest.kt` for the Spark colour, cover packing,
migration, labels, arcs, and split/full-band data. The locked 2026-09-16 revisions of
`docs/product/WATCH_RING_DESIGN.md` and `docs/product/WEAR_GLANCE_DESIGN.md` define the pair
geometry and colours; the Glance document's 2026-10-01 revision records paired-row measurements
on round and notround devices.

- [x] Spark's half carries `#186020` and its own far marker, distinct from the plan's.
- [x] The Glance shows the pair as one row with two arcs and two percentages.
- [x] A ring selected before the update is still selected after it.
- [x] The unnamed Codex plan window reads exactly as it did before.

Non-goals for this phase:

```text
quantising the arc through stepped title tokens — the face is measured to 21.7 and 179.95°,
  and an inexact arc would be the only one on it
a third pool in one band — the band has two halves and two markers, and that is the shape
folding the outer half into its band's slot, which would make every band splittable; it lands
  only if the spike above comes back positive on both precision and parsing
```

### Phase 19 — WardPulse mark in the phone app bar

Status: completed as of 2026-10-01 by `f98cf53`.

Rationale: the retained `WardPulse` title identifies the app in words, while the leading brand
mark makes that identity visible across every phone screen. The color metal-and-ring mark was
chosen for this compact placement because it stays distinct in light and dark themes. The mono
asset remains a quiet watch-face watermark: it already contains `WARDPULSE`, so placing it
beside the title would duplicate the word instead of adding the mark.

Landed:

- the color mark in `AppBar.leading`, beside the unchanged `WardPulse` title;
- PNG runtime assets at 1×, 2×, and 3× density, generated by the existing brand export flow and
  declared through the Flutter asset bundle;
- no new package or rendering dependency;
- widget regression coverage for the mark and retained title in both platform brightness modes,
  plus owner verification in the light and dark themes.

Acceptance:

```text
the color WardPulse mark leads the retained WardPulse title
the app bundle resolves 1x, 2x, and 3x raster densities at the intended logical size
the mark and title remain present in both light and dark themes
the phone adds no dependency to render the app-bar mark
the mono wordmark remains reserved for watermark use and is not duplicated beside the title
```

---

### Phase 20 — three upper cells on the watch face

**Selected-zero revision 2026-10-13.** The retained-zero ring and legend treatment changes
no upper-cell geometry. The current `WATCH_RING_DESIGN.md` revisions own the complete cells
at integer origins `(152,114)`, `(204,100)`, `(256,114)`, the three-unit downward move, full
temperature labels and shortest radial border fades. The acceptance below follows those
current revisions; new exhausted-state review art must use the same geometry.

Status: design locked 2026-10-09 in `docs/product/WATCH_RING_DESIGN.md` (upper-cell revision,
with the melt-length and cell-layout corrections of the same day), and the first implementation
pass is in the tree. `tools/render-watchface.mjs` now bounds the
three ring slots with a full-canvas `BoundingBox` and declares each band at the 20 units it
paints; `watchface.xml` is regenerated from it. The nine ring textures came out byte-identical,
and the review-art generators and the Wear complication sources are still untouched. The rest of
this entry is what the design commits the remaining passes to.

Unrelated to the cells, and found while reading the system face picker on 2026-10-09: the
picker was advertising the face with `drawable/preview.png`, unchanged since `2c5aec3`, which
draws the side-by-side `RING 1` / `RING 2` wireframe — the first non-goal in the design
baseline. No generator owned that asset at the time. It is now generated from the Primary
baseline with the face review previews by `tools/render-watch-ring-designs.mjs`. Recorded under
*Previews are generated — and the picker's showed the first non-goal* in
`docs/product/WATCH_RING_DESIGN.md`.

That the picker advertises the face *with that file* was inferred from the metadata chain —
picker, to `watch_face_info.xml`, to the declared drawable — and never seen. The staleness of
the file was read off the file and is not in doubt; the conclusion about the picker was not.
Measured on `emulator-5554` on **2026-10-11**, the only direct reading of the picker shows it
rendering the face live, watermark and preview complication data, with nothing of the shipped
file in it. The find stands as written; the baseline carries the correction under *Surface
correction 2026-10-11*. Generating the asset never rested on that inference, and the same
session confirmed the half that matters: the installed package was pulled off the device and its
`res/drawable/preview.png` is byte-identical to the tree, so the generator's output ships
intact. An image the package ships and no generator rewrites will lie wherever it is shown.

An audit of that work on **2026-10-11** found no violation of its own specification and five
gaps it had not covered, all pre-existing. Closed in the same pass: every review board now has a
preview, derived from the board list rather than a second list beside it — seven had none, three
of them rows the baseline labels *baseline*; the cell hairline's geometry is described as what
it draws, inscribed in the well at radius 20.0 to 21.0 rather than inset a quarter of a unit,
which four places had claimed and none of which moved a pixel; the review boards carry the
face's two well alphas instead of painting all three cells opaque; and the shipped portrait now
composes the quiet watermark the face draws, which retires the brand copy of that same picture
(`docs/DESIGN_ASSETS.md`).

Rationale: the face says a great deal about AI spend and nothing a watch is ordinarily expected
to say. The band above the clock has been reserved for a weather glance since the 2026-07-25
baseline and has carried nothing in that time, which is the weakest form a reservation can take
— space that is spent but not used. Giving it to the wearer as three customizable cells spends
it on whatever that person actually wants on their wrist, and costs the product nothing it was
using. The weather that reservation was held for arrives in the end anyway, and not as a
complication: WFF reads it from a built-in source in an expression, so the face draws the
temperature and the UV index itself beneath two of the cells and still hands all three to the
wearer. What the reservation had wrong was not the content but the price it assumed.

The obstacle was the slot budget, not the space. A scene holds at most eight complication
slots, the face has used all eight since the baseline, and three cells need three. They are
paid for by folding each legend strip into its own band's slot. That became possible only after
measuring what `BoundingArc` does.

Measured during the design (recorded with its numbers in the design baseline):

- a ninth `ComplicationSlot` is rejected in format versions 2 and 5, and `sceneElement.xsd:45`
  states `maxOccurs="8"`, so the cap is not a version problem;
- `BoundingArc` clips its slot's drawing to its own band **and** halves the stroke — declared 40
  paints 20.1/19.9/20.5 bounded by an arc, 40.4/44.3 bounded by a full-canvas box. The long-held
  belief that WFF paints half the nominal was a property of our own markup, not of the platform.
  Without the arc a band also re-centres, painting 134–175 where the shipped one paints
  133.8–154, so the declaration has to give `width` twice the centre line to hold each band in
  place. Those spike edges are quoted whole because two scans of the capture differ by most of a
  unit on them; the baseline carries the readings. The nine ring-type textures are **not**
  affected: a radial alpha profile shows their ink already confined to its own annulus (135–153
  for `ring3_type_day`, 183–201 for `ring1_type_month`) and fully transparent inside, so they
  need no clip and no redraw;
- the clip also made the melt short, which only the first pass revealed. A `BoundingArc` cuts
  across a band and never along it, so it shaved a `ROUND` cap's disc radially instead of
  shortening its reach: a 40-unit stroke ends in a disc of radius 20, and the surviving wedge
  reached its full 20 units only at the band's outer edge, `sqrt(20**2 - 10**2)` = 17.3 units on
  the centre line. The melt was inset by the full 20 either way, so the visible arc fell about
  0.7° short at each end. Measured on the centre lines before and after the restatement: ring
  102 at 36% went from 128.10° to 129.55° against a true 129.564°, while rings 101 and 105 did
  not move, neither of them using a round cap. The two-cap cutoffs halve with the cap, to 1.66%
  / 1.89% / 2.21%;
- review art was right and the face was wrong, for as long as both have existed. The boards
  always drew the measured model and the true remainder; `just check-designs` never caught the
  disagreement because it compares the art against its own generator, never against the face;
- a tap on a cell reaches the cell and not the band beneath it, even when the band's slot claims
  the whole canvas, so a third-party complication in a cell opens its own app;
- markup inside `<Complication type="EMPTY">` does not render, so an empty cell's well is scene
  chrome drawn behind the slot;
- a filled slot's content draws over scene chrome declared earlier in the document, and an empty
  slot lets that chrome through. A cell bound to `DAY_OF_WEEK` drew `Tue` on its own well with a
  deliberately hostile pure-red chrome invisible beneath it, while two cells left `EMPTY` showed
  their chrome carrying `[WEATHER.TEMPERATURE]` and `[WEATHER.UV_INDEX]`. This is what lets the
  default weather cost no complication slot, which matters because `defaultProviderType` is a
  closed enumeration with no weather entry — a face cannot bind a cell to weather even where a
  weather provider is installed, and none of the 23 providers on the round AVD is one;
- a well at the strips' `#eb0b0e0c` leaks what lies under it. Over that red chrome it read
  `30, 13, 11` at three points, against `17, 22, 20` for the face beside it — alpha `0xeb` is
  235/255, so 7.8 % of the layer beneath comes through, and it drops green and blue below the
  surrounding face as well as adding red. The same markup at `#ff0b0e0c` read `11, 14, 12`, the
  declared colour exactly. A cell's own well is therefore opaque, while the strips keep theirs
  translucent because nothing but the lift lies under them;
- the first cell layout was uneven, and measurably so. Three cells of 48 units in a straight row
  at `y=134` stood 2.95 units from the inner band at the ends and 18.80 in the middle — a spread
  of 6.4 times — with 2.0 units left under the lowest cell before the clock. A straight row
  under a circular boundary cannot do better. Moving the centres onto an arc concentric with the
  face, radius 106.8 at −29° / 0 / +29°, makes that gap 6.00 for all three by construction, and
  the diameter falls to 42 to buy 7.41 to the clock and 11.48 between neighbours. The arc also
  evened the radial lift under the cells, from 82 and 99.3 to 97.80 and 99.02, so all three
  wells now composite to the same `19, 24, 22`;
- a trailing mark pulls a centred string off the digits. `18°` centred as a whole string put its
  digits 2.5 units left of the cell axis; shifting the line box right by half the mark's advance
  put them at 224.5 against 225, and the correction is independent of the digit count;
- an empty cell was indistinguishable from a filled one except by the absence of text, which
  reads as a fault rather than as an invitation. A cell showing nothing now takes a graded well,
  `#ff0b0e0c` to `#ff242a27` across the outer 45 % of its radius — rim `36, 42, 39` against a
  surrounding `19, 24, 22`. A hairline ring read more literally and was rejected as a border
  around a card, which the non-goals refuse;
- a changed slot does not pick up its declared default on an installed face. Cells on the freed
  strip ids drew nothing; cells on unused ids drew nothing either, logging `id[201] : EMPTY`;
  only uninstalling and reinstalling the package made them take their providers. The binding is
  held against the installed face, not against the slot id, so renumbering is not an escape. An
  uninstall is available while debugging and is not something a wearer will do, which is what
  makes the migration risk below a real one rather than a cosmetic one;
- the wearer's ownership of the cells is a property of the format, not a choice this phase made.
  The watch face package ships zero `.dex` entries and declares `android:hasCode="false"` with
  no activity and no service; the drawing process is
  `com.google.wear.watchface.runtime/DeclarativeWatchFaceRuntime0`, and the provider chooser is
  a system activity in `com.google.android.wearable.sysui`. A WFF face has nowhere to run an
  editor, so it cannot own slot configuration, and neither can the phone app. Readings in
  `docs/ANDROID_TOOLCHAIN.md`, *Watch Face Format*. What the chooser offers for a slot carrying
  `EMPTY` was not reached on the AVD and stayed unverified until 2026-10-11.

  Found **2026-10-11**, and it is why that last sentence stayed unverified for so long: the
  chooser could not be reached at all. Ownership being the format's does not make the editor
  reachable — the package still has to ask for it, through `Editable` in
  `watch_face_info.xml`, which defaults to false and withholds the Edit button from the
  favorites list. This face declared only `Preview`, so from the day the cells shipped no
  wearer could configure one. Measured on `emulator-5554`: `dumpsys wear_service` reported
  `Editable Resource Only WatchFace=false`, the picker offered WardPulse no edit affordance
  while the neighbouring face had one, and a direct chooser launch failed with
  `Failed to find watch face info`.

  Declared and read back the same day, on the same AVD. `dumpsys wear_service` now reports
  `Editable Resource Only WatchFace=true`; the picker offers `Edit watch face`; the editor
  opens on the three upper cells and exposes those three targets and nothing else — `Day of
  the week`, `Add complication`, `Add complication` — which is slot 201 with its default and
  202/203 empty. Selecting a cell opens the chooser, and **what it offers for a slot carrying
  `EMPTY` is now known on this AVD**: eighteen entries counting `Empty` — ten stock Wear
  providers, one that ships only with the emulator image, and all six of WardPulse's own,
  which is the number its manifest declares. Putting `Battery` in the middle cell drew `100` as
  text inside the hairline with no arc, and the cell was set back to `Empty` afterwards. That
  was first recorded here as a witness for Upper cells rule 8; it is not one. The runtime bound
  the slot as `type=3`, `SHORT_TEXT`, so the face drew text because it was handed text. It
  witnesses rule 7 instead, and the retraction, with what a ranged value in a cell would take,
  is under rule 8. One AVD and one Wear build; nothing here claims other devices. Recorded
  under *Editing correction 2026-10-11* in `docs/product/WATCH_RING_DESIGN.md`, Upper cells,
  rule 5.

  **Acceptance read back on the device, 2026-10-11.** With the face from the editability fix
  installed, the lines of this phase that need a watch were taken on `emulator-5554`. One screen
  pixel is 1.17 design units at 384, so anything inside ±0.6 units is inside a pixel.

  The face declares eight slots — `101, 102, 105, 106, 109, 201, 202, 203` — and
  `just validate-watchface` passes at format version 2. Measured from the capture, along the
  horizontal centre line with edges taken at half-maximum:

  | Band | Width | Centre, from the face axis |
  |---|---:|---:|
  | outer | 19.92 u | 191.60 u |
  | middle | 19.92 u | 168.16 u |
  | inner | 19.92 u | 143.55 u |

  against the locked 20.2 and the declared 192 / 168 / 144 — the reading this phase asks for
  *on the device rather than derived*. The left cell's hairline measures **41.0 units across on
  both axes**, centred at 172.3, 131.2 against the declared 173, 132 and a `ringDiameter` of 41.
  The legend strips' colour chips centre at **291.2 / 312.3 / 333.4**, which is the declared
  `y=283 / 304 / 325` plus the 18-unit line box's half — every row inside 0.8 units. And the
  measured inner band puts its inner edge at 133.59 from the face centre against a cell's
  outermost point at 127.80, a **clearance of 5.79 units** where rule 1 derives 6.00.

  **The melt spans the true remainder.** Sampling the capture along each band's measured
  centre circle in tenth-degree steps — a pixel counting as lit when its saturation passes 35
  and its brightest channel passes 80 — the inner band, the tightest, whose strip reads 35%,
  is lit in one unbroken span from **234.3° to 359.8°**: **125.50°**, against a true remainder
  of `0.35 × 359.9` = 125.97° and a computed start of `(1 − 0.35) × 359.9` = 233.94°. The start
  is 0.36° late and the span 0.47° short, which at that radius is about one pixel of arc.
  Before the `BoundingArc` came off, the entry above records the visible arc falling about
  0.7° short **at each end**, near 1.4° in all; it is 0.47° in all now, and what remains is the
  sampling grid rather than the face. That is the device confirmation of a fix which until now
  had only the restatement behind it.

  Only the inner band gives a clean reading, and the reason is worth stating so nobody reads
  the others as drift. The same test puts the outer band at 68.5% and the middle at 74.8%
  against strips reading 75% and `100% · 70%`, because at those radii it also catches the
  ring-type texture and the dark Spark half of a split band. Those two figures are the method's
  limit, not the face's, and are not recorded as readings.

  Three behaviours were exercised rather than measured. A tap on a filled cell opened that
  cell's own provider — `Battery` in the middle cell opened the watch Settings app, never
  WardPulse — which is the acceptance line, now seen on the shipped face rather than on the
  2026-10-09 spike. A tap on a cell that renders empty does **nothing**: it does not fall
  through to the band slot beneath it or to the watermark's `Launch`. And in ambient, with two
  cells filled, both stayed and dimmed whole — text and hairline together — while the empty
  cell's recess stayed and no cell showed two readings at once, which is that acceptance line as
  far as it goes without a weather source on the device.

  **The nine ring-type textures are unchanged**, which settles the repository half of that
  acceptance line: `git diff --stat` across `30402f4..1171626` over
  `apps/watchface_wff/src/main/res/drawable-nodpi/` is empty, and the last commit to touch them
  is `82053af fix(watchface): bake the ring type into four dimmed sweeps`, before the upper-cell
  work began. The device half does not follow from that and was not taken: the payload on the
  AVD carries no budget ring, so no period type was being drawn and nothing was observed.

  The boards were compared against the same capture by hand, which `just check-designs` cannot
  do; the six band edges agree exactly, and the reading is in `docs/product/WATCH_RING_DESIGN.md`
  under *Review variants*.

  **The weather cells said nothing, 2026-10-12.** Once a real reading reached the AVD the two
  chrome cells read `51` and `0` — a number with no unit and a number with no subject — because
  both templated the bare expression from the day the cells shipped, while the board, the
  shipped preview and the typography rule all drew `18°` and `UV 7`. They now carry `%s°` and
  `UV %s`. The acceptance line *the temperature's digits sit on the cell axis, not its string*
  becomes true for the first time: the box had carried the degree mark's offset since the start
  while drawing no mark, so it was correcting for something absent. Recorded with the reasoning,
  and with the one width that is estimated rather than measured, under *Reading revision
  2026-10-12* in `docs/product/WATCH_RING_DESIGN.md`, Upper cells, rule 11.

Scope when the implementation runs:

- `tools/render-watchface.mjs` — three cell slots of 42 units on new ids, centred on the arc of
  radius 106.8 at −29° / 0 / +29° (boxes at `152, 111`, `204, 97`, `256, 111`), the wells as
  scene chrome with the temperature and UV index read from the built-in `WEATHER.*` source and
  declared ahead of the first slot, an opaque `#ff0b0e0c` well inside each filled cell and a
  graded well where a cell shows nothing, the cell typography and the per-type treatment (text
  only in a 37×18 box at `x=2, y=12`, no `TITLE` and no provider icon, the temperature's box
  shifted right by half the degree mark; a tinted 21-unit `MONOCHROMATIC_IMAGE`; a
  `RANGED_VALUE` as text rather than an arc), the folded strips, and the combined `TITLE`
  vocabulary. The `BoundingBox` and the restated band declarations are **done** — see the first
  pass above;
- `tools/render-watch-ring-designs.mjs` needs **no geometry change**: its drawing path already
  works in the measured model (`outer = size * 0.4264`, `thickness = size * 0.0449`, centre
  lines 191.88 / 167.89 / 143.91 against the face's 192 / 168 / 144), so the boards and the
  watch agree for the first time as of the first pass. It changes only for what the cells add to
  the boards;
- `apps/wear_android/.../complication/WatchSummaryComplications.kt` and the Wear manifest: the
  three strip services fold into the ring services, which gain the strip label on `TEXT` and the
  combined token on `TITLE`.

Migration risk, named here rather than in the design baseline: the Wear complication sources
already carry comments reading *class name kept for installed faces*, because earlier slot
reshuffles broke faces that were installed at the time, and Split band rule 4 records the exact
shape of that damage. This revision moves more slots than any revision before it — three slots
change what they draw, and three more are new. An installed old face paired with the new app
will show wrong data until both are updated, and keeping the service names stable cannot prevent
it, as the 2026-09-16 revision already learned. The face and the app have to ship together.

Acceptance:

```text
the face declares exactly eight complication slots and the validator passes
three cells render above the clock, customizable; the left one ships bound to DAY_OF_WEEK and
  the other two ship EMPTY over the face's own temperature and UV chrome
the three cells sit on the arc, not in a row: the middle one rides 14 units above the outer two
  at integer origins 152,114 / 204,100 / 256,114; the row is three units below the former concentric layout
  derived inner-band gaps are 8.8577 units at left/right and 8.8000 at middle, not new device measurements
a filled cell's opaque well covers the chrome beneath it with no tint carried up from it, and
  emptying that cell brings the reading back
the face shows the graded well, not a zero or an empty string, when weather is unavailable
a cell draws text in the face's own label voice, with no provider TITLE, icon, or arc, and a
  MONOCHROMATIC_IMAGE tinted to the face's text colour
a tap on a cell opens that cell's own provider, never the WardPulse app
an empty cell shows a recessed well — no mark, glyph, or wordmark — carrying only the weather
  reading where the face declares one under it; a cell showing nothing at all takes the graded
  rim, so a filled cell and an empty one are told apart without reading their contents
the complete temperature label (including °C/°F) is centred in the 37-unit box with no numeric-only shift
the three legend strips render from their own bands' slots at y=283 / 304 / 325
with one and two rings the strip stack fills from its bottom row and leaves no gap mid-stack
the tightest remaining is the topmost occupied strip row at one, two, and three rings
the rendered band stays at the locked 20.2 units, in the same place, after the bounding
  element changes, measured on the device rather than derived
a partially spent band's melt spans the true remainder on its centre line, not one cap short
each band's ring type still registers with its band, the nine textures unchanged
in ambient the occluder and the recess both stay and every value dims — the complication in a
  filled cell, and the weather showing through an empty one; the filled cell's well still hides
  the chrome under it, so no cell ever shows two readings at once
in ambient each legend strip dims with its whole row rather than switching off, so the credits
  and the money — which appear nowhere else on the face — survive; the variant sits on the row's
  enclosing group, the only place that reaches an accent painted from the ranged-value colours
just check-designs passes, and the boards are compared against a device capture by hand —
  check-designs only proves the art matches its own generator, never that it matches the face
```

Non-goals for this phase:

```text
the recovery marker on the face — it stays the Phase 15 open question, and no cell is
  reserved for it
a WardPulse-owned micro-widget beyond sync freshness; the others are offered, not committed
a user-facing switch for whether a cell survives ambient — no configuration element may appear
  inside a Complication, and a BooleanOption may not contain a ComplicationSlot, so the face
  cannot offer the choice around slot content either way
raising the eight-slot cap, or the three-ring cap, by any means
a fourth cell, or a cell below the clock
a complication slot spent on weather — weather is the face's own chrome and costs no slot
a small arc inside a cell; a ranged value in a cell reads as text, so the face keeps one
  arc language
```

---

### Phase 21 — user-facing Vocs guide

Status: completed on 2026-10-14 for the user-guide documentation, user-only publication
and theme-matched gallery, including the task-illustration and practical setup/issue-reporting
follow-ups below.

The initial publication kept development, architecture, provider-reference and design
documentation in their existing sections alongside a guide for installed-app users. Its
landing linked to Getting started and its sidebar listed eight task pages ahead of Project.
That mixed presentation is historical and is superseded by the user-only revision below.

The Cursor token-help prerequisite was accepted on 2026-10-14 in normal and narrow
320×640/font-1.5 emulator layouts, including keyboard and Cancel-retention checks. Its
scoped host phone gate passed 392 Flutter tests, 64 native cache assertions and
28 native widget assertions, plus formatting and analysis. The eight guide drafts
passed separate source review and a complete repeat prose review with zero findings.
The integrated source-citation gate checked 79 Markdown/MDX source files, and the Vocs
build produced 63 generated files. That initial completion covered the user guide only; live credentials and
remaining provider authentication, physical phone/Wear hardware, release and
internal-testing acceptance remain open. On 2026-10-14 independent and coordinator full
reviews reached ZERO; initial-publication browser checks covered all eight guide routes at 1280/390px, all
Source notes at 390px, and nine direct anchor opens plus six TOC clicks across
390/1280/1440px with target titles fully visible.

Current user-only revision — **2026-10-14**:

The public site contains ten authored pages: the overview, eight task guides and privacy
policy, without developer Source notes, internal sidebars or direct engineering-reference
routes. Eighteen technical presentation adapters were removed; their original documents
remain with their repository owners. Root README and the landing begin with a product
introduction and up to three showcase screenshots per platform; Android phone and Wear OS
are one platform, with three selected captures total. Guide reuse is optional. The
user-docs skill governs public prose and screenshot freshness.

Three real anonymous UI captures were accepted on 2026-10-14: phone Dashboard at 864×1920,
Wear Glance and watch face at 500×500 each. The three canonical PNGs, public symlink aliases,
homepage/README galleries and complete screenshot index are integrated. They are not
Mock/demo screenshots. The post-repair citation gate checked 63 Markdown/MDX source files,
and the Vocs build produced 27 generated files; authored public pages were counted
separately. After the last fix, complete independent and coordinator source/rendered
reviews reached ZERO. Browser review covered all nine guide/privacy pages at 1280×900
and 390×844, the homepage at 390px wide and 1440×900, actual menu/search/TOC navigation
and direct anchors, with readable full-frame gallery previews and original image links
matching the canonical PNGs. The earlier 79/63 and Source notes evidence above remains
initial-publication history.
This revision does not close live-provider authentication, physical hardware, release or
internal-testing acceptance.

Theme-matched gallery follow-up — **2026-10-14**, completed:

Four canonical PNG variants and their index are integrated for three showcase subjects on
the single Android+Wear platform. Both real anonymous phone themes are 864×1920, with clean
status bars captured using OS icon-visibility controls: no notifications were dismissed,
no Mock/demo data or app-screen retouching was used, and temporary device state was restored.
Wear and the watch face have a confirmed fixed dark appearance; their unchanged 500×500
captures are reused in both documentation themes without fabricating a light counterpart.
The index records themes, Date added and actual capture/verification dates.

Ten Vocs live-change/reload cases covered Light/Dark/System and 1440/1280/390px layouts,
including actual mobile theme controls. Six README manual/automatic cases at 390/1440px
included a manual choice opposite the OS theme. Active previews, original-image links and
keyboard navigation matched the selected theme. All nine guide/privacy pages were reviewed
at 1280px Light and 390px Dark, including actual search, TOC clicks and direct anchors.
HTTP checks confirmed ten public routes returned 200, eighteen retired routes returned 404,
and `/index` returned 308 to the canonical homepage.

Complete independent and coordinator post-last-fix source/rendered reviews reached ZERO.
On the accepted gallery revision, the required documentation check passed for 63 Markdown/MDX
source files and 27 generated files, and the final user-docs skill validator passed. Earlier
publication evidence above describes the initial and pre-theme states. This completed slice
does not close live-provider authentication, physical hardware, release or internal-testing
acceptance.

Task-illustration follow-up — **2026-10-14**, completed:

Real Providers connection examples, Widget selection and launcher results, and useful
Getting started/Dashboard/Watch illustrations are integrated near their steps with concise
captions and verified watch-ordering explanations. The indexed set has 19 canonical PNGs:
16 phone variants at 864×1920 and three circular Wear images at 500×500 RGBA. Guide images
remain outside the three-subject landing/README cap. Captures are real and anonymous, with
empty credential fields and no Mock/demo or UI retouching. Wear corners are transparent
while inside UI is preserved; the [asset index](assets/README.md#screenshot-index) records
the clean face and restored device state.

Owning Native run `a56aba41-7e97-46ba-8f7c-d9fee874f20e` reached quiescent DONE with independent
review ZERO, stage-only and no commit. Its frozen prose/assets were preserved throughout.
Runner and coordinator each freshly passed the three required checks on that accepted
revision: `just check-docs` (63 Markdown/MDX citation sources and 27 generated files), the
user-docs skill validator and `git diff --check HEAD`.

Rendered acceptance covered ten public routes in 80 layouts (ten pages × two themes × four
widths), all 19 original-image clicks with matching theme variants, and eight fresh GitHub
gallery cases. All 50 earlier heading IDs remain, with three meaningful Watch subsections
bringing the total to 53; 106 actual deep-link opens at 390/1280px verified visible headings.
Complete independent and coordinator post-last-fix source/rendered passes reached ZERO,
including subtle frames, a clean round face and quiet readable Last updated. This work does
not wire section links into the app or close live-provider authentication, physical hardware,
release or internal-testing acceptance.

Practical setup and issue-reporting refinement — **2026-10-14**, completed:

Scoped prose removes generic build-distribution filler, explains connections to existing
accounts or Admin keys, and gives verified Chrome/Firefox/Safari cookie steps. Budget and
alert examples use four actual light/dark phone captures of unsaved drafts, cancelled with
original settings verified unchanged. A single owning issue-format page requires Actual
behaviour, Expected behaviour and Steps to reproduce, with optional Notes, and links to
GitHub issue creation. The screenshot skill specifies neutral frames and optional editorial
action outlines while preserving clean originals. The eleventh public page, two contextual
icon outlines on the Dashboard example and repository navigation are integrated.

Complete independent and coordinator primary source/rendered reviews reached ZERO. Actual
acceptance covered 11 pages in 88 layouts, 130 direct opens across 65 anchors, 54 native
permalink links and all 23 original images; all 53 earlier section IDs are preserved. The
owning Runner's default documentation check, skill validator and whitespace check passed
before this prose closure. The root and `/wardpulse-docs` static builds were verified locally.
Earlier accepted evidence and open live-provider, physical hardware, release and
internal-testing work are unchanged.

Guide scope:

- Getting started: available installation route, supported phone/watch prerequisites, first
  launch and local-first data/credential expectations, with links to the privacy policy.
- Providers: prerequisites and the actual UI steps for each supported connection method;
  connecting, reconnecting and disconnecting; distinctions between API keys and account login.
- Dashboard: usage and remaining balances, credits, alerts and history; unknown values, real
  zero/exhaustion, last successful update time and stale cached data.
- Watch and home widget: pairing and surface setup, selecting watch rings/complications and
  configuring widget metrics, with the current platform limitations made explicit.
- Sync: manual and automatic refresh, background delivery, offline/restart recovery and how
  stale data differs from a successful fresh poll.
- Troubleshooting: safe steps for missing data, rejected credentials, provider failures/rate
  limits, delayed phone-to-watch delivery and widget updates; never request secrets or raw
  provider payloads in diagnostic instructions.

Keep authoritative guide content under `docs/product/user-guide/` and expose it through thin
Vocs pages. Use current screen/control names and user-facing guide, privacy or provider-account
help links; keep engineering references in their repository owners. Examples and screenshots
must be approved for public sharing, with anonymous or redacted data. This requirement does not close the remaining live-provider,
release or hardware acceptance work.

Acceptance:

```text
the landing page and sidebar expose a discoverable user-guide entry
a first-time user can connect a supported provider, interpret the dashboard and set up the
  available watch/widget surfaces without repository or developer-toolchain instructions
connection prerequisites, current UI steps and recovery instructions are checked against the
  accepted application build, with unsupported/unavailable paths clearly identified
unknown, zero/exhausted and stale values are explained with sanitized examples; offline and
  background sync behavior agrees with the implemented persistence and delivery semantics
guide pages reuse authoritative Markdown, keep technical references separate, and contain no
  credentials, private account data or sensitive provider payloads
just check-docs passes, including the repository source-citation gate and Vocs build
```

---

## 20. Testing strategy

### Rust core

- unit tests for aggregation;
- unit tests for budgets;
- unit tests for projections;
- unit tests for alerts;
- fixture-based provider normalization tests;
- golden snapshot tests.

### Flutter phone app

- widget tests for dashboard cards;
- widget tests for provider states;
- widget / App Widget payload tests for the Phase 14 home-screen surface;
- snapshot/golden tests for key dashboard screens where practical;
- integration smoke test on Android emulator.

### Wear OS app

- Compose UI tests for navigation;
- preview coverage for different watch shapes/sizes;
- emulator smoke tests;
- physical watch smoke tests before release.

### Watch face

- WFF validation;
- memory validation where available;
- install test on emulator;
- ambient mode review;
- tap target review.

---

## 21. Local development on Ubuntu

The Android part should be fully developable on Ubuntu.

Required tools:

```text
Rust toolchain
Flutter SDK
Android Studio
Android SDK
Android NDK
JDK
Gradle
Wear OS emulator images
```

Optional but recommended:

```text
just
cargo-nextest
cargo-audit
cargo-deny
flutter_rust_bridge or UniFFI tooling
real Android phone
real Wear OS watch
```

Mac is not required for Android, Wear OS, WFF, Rust core, Flutter Android, APK/AAB builds, or Google Play publishing.

Mac becomes relevant only for iOS, watchOS, visionOS, Xcode, Apple signing, and App Store publishing.

Maintenance follow-up (2026-10-02) — installation verification completed in `6b73899`.
`install-phone` now requires an explicit phone serial, propagates the real `adb install` result,
and verifies that the package's `lastUpdateTime` changed. Its fake-`adb` regression covers the
missing serial, install failure, unchanged timestamp, and successful installation; the verified
workflow is recorded in `docs/ANDROID_TOOLCHAIN.md`.

The separate storage follow-up closed on 2026-10-02: the phone AVD was recreated with a 24 GB
data partition configured before its first boot. `7fb15d2` records that recipe in
`docs/ANDROID_TOOLCHAIN.md`: `/data` is materialized on first boot, and an image with snapshots
cannot be resized later. After boot, `df -h /data` reported 23 GB at 6% used; `just install-phone`
installed the full 147 MB debug APK and left 22 GB free.

Recreating the AVD removed the old `wardpulse-logged-in` snapshot and its Claude, Cursor, and
Codex sign-ins. Restoring those sign-ins and recreating the snapshot are owner-owned setup, not
development work or code blockers. Phase 18 no longer depends on that setup.

---

## 22. CI plan

Initial CI should be simple.

```text
core.yml
  cargo fmt --check
  cargo clippy
  cargo test

phone-android.yml
  flutter analyze
  flutter test
  flutter build apk --debug

wear-android.yml
  ./gradlew test
  ./gradlew assembleDebug

watchface.yml
  official WFF schema validation
  ./gradlew lintDebug assembleDebug bundleDebug

designs.yml
  review art still matches its generators (SVG only)

docs.yml
  documentation site builds
```

Every workflow that can reach a shared contract also runs
`tools/validate-fixtures/validate_json.py`: it validates the golden fixtures and checks that the
watch payload version agrees across the schema, the phone, and the Wear store.

Manual release Stages A and B are implemented in
[release-android.yml](../.github/workflows/release-android.yml), jobs `build` and `publish`:

```text
release-android.yml
  workflow_dispatch on main; original exact source SHA and source versions
  import persistent upload and separate Push signing after public tooling setup
  guarded phone/Wear/legacy AABs and direct installers plus producer Push APK
  verify seven signatures, fixed certificate pins and exact embedded Push bytes
  separate import/build/verification steps; remove private signing state before upload
  upload seven binaries, SHA256SUMS and sanitized provenance under an attempt identity
  download the exact successful build artifact ID, retaining its originating attempt
  re-read immutable source metadata; independently verify the exact nine files and receipts
  authenticate and paginate release conflicts; independently peel any existing tag
  repeat conflicts; create only a full-SHA draft requesting make_latest: "false"
  re-observe release/tag bindings after creation and upload; confirm all nine assets
```

The [manual build instructions](product/RELEASE_CHECKLIST.md#manual-android-release-build-stage-a)
own Environment/manual invocation, the seven installer/bundle outputs plus receipts, exact
artifact/origin identities and signing cleanup. Build retains `contents: read`; publication
uses only `contents: write` without signing secrets or broader credentials. Upload-signed
installers do not promise debug/Play update compatibility. Publication preserves partial
state on failure, refuses every preexisting release for the tag and requires deliberate Owner
resolution before retrying after creation. It never separately creates or moves a tag, edits
or publishes a release, or overwrites assets. Prechecks do not provide atomic exclusion or
protection from future external mutation. Hosted permissions, provisioning/cleanup, transfer,
draft creation, rerun/cancellation and partial-state acceptance remain pending. This source
implementation does not close separate local signed-artifact, Play delivery or runtime gates.

---

## 23. First evening MVP

A realistic one-evening prototype should avoid real provider complexity.

Build:

- Rust mock dashboard snapshot;
- Flutter phone dashboard with today/week charts;
- Kotlin Wear OS app with compact mock dashboard;
- optional static WFF watch face if time remains.

Do not build:

- real provider auth;
- production secure storage;
- Play Billing;
- multiple real providers;
- active agents;
- polished watch face customization.

Success criteria:

```text
phone app shows a convincing AI usage dashboard
watch app shows useful compact summary
architecture proves Rust core can feed both surfaces
```

---

## 24. Current recommended next step

See [Product roadmap beyond the Android MVP](#25-product-roadmap-beyond-the-android-mvp)
for the planned sequence. These milestones do not establish release readiness or dates.

## 25. Product roadmap beyond the Android MVP

Owner direction recorded on 2026-10-15. These are planned milestones, not shipped features
or release acceptance. The public summary is owned by
[Roadmap](product/user-guide/ROADMAP.md).

- **Release 0.1.0:** first public Android phone/Wear OS release, with the home widget and
  watch face. No release date or distribution route is committed here.
- **Multi-account:** multiple accounts of the same provider, with separate identities,
  credentials and usage. This is the nearer follow-up milestone; the current single-connection
  model is not multi-account support.
- **iOS release:** a later iPhone product milestone. This does not start iOS implementation
  or add watchOS to the committed scope.
- **Other providers:** support for additional AI providers.
- **Agent Bridge (MCP):** a further-out service through which agents can send important
  messages to WardPulse. Replies are a possibility, not a requirement or committed capability.
  Even one-way notifications need a full hosted backend, including WardPulse accounts, access
  keys and subscription management. Its authentication, billing, retention and delivery
  contracts remain future design work; no service, API or commercial plan exists by virtue of
  this roadmap.

The public roadmap shows five known milestones at irregular positions without connecting
lines. One broad background arrow points down through the centre to suggest overall
direction, without linking particular milestones. Multi-account is slightly nearer than
iOS; all five use the same filled marker. The iOS and Other providers headings, body copy
and markers share a slightly muted appearance. Many quieter,
anonymous question-mark points form an irregular background field, each paired with a
recognisable smaller filled marker. Its density adapts to the available space, keeping the
known milestones clear in front. A background position may be occupied by a real milestone
through an ordinary documentation update; it is not a named feature, promised release or
interactive editing control. Organic cloud-like fog below Agent Bridge implies the
unannounced future without explanatory labels. This is a decorative field independent of
the public prose's paragraph count, with soft irregular edges rather than a rectangular
gradient panel. These decorations add no announced feature, commitment or interaction,
and must not obscure the known milestones.

This future service does not change the Android product's current local-first provider
credential model. It does not authorize uploading provider credentials or usage data to a
WardPulse backend. Any later service design must define its own data and security boundaries
before implementation and update the applicable privacy guidance.
