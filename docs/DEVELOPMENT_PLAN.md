# WardPulse Android — Development Plan

Updated: 2026-07-24

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
- show compact dashboards on Wear OS;
- expose a lightweight Watch Face Format watch face for glanceable state and quick app launch;
- support multiple accounts per provider;
- support user-defined budgets/limits when provider-side limits are unavailable;
- stay possible to develop fully on Ubuntu for the Android part.

---

## 2. Product shape

The Android ecosystem has three user-facing surfaces.

```text
Android phone app
   ↓
Main dashboard, settings, credentials, provider sync, charts

Wear OS app
   ↓
Compact dashboard, provider details, alerts, recent sync state

WFF watch face
   ↓
Glanceable today/week state + tap target to open the Wear OS app
```

The phone app is the primary product surface. It should feel like a compact analytics dashboard rather than a simple counter.

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

### MVP screens

```text
Home / Overview
Providers
Provider details
Budgets & credits
Charts
Settings
Sync status / logs
About / legal
```

### Home / Overview

Shows:

- today spent vs daily limit;
- week spent vs weekly limit;
- month spent vs monthly limit if configured;
- remaining budget;
- additional credits if known;
- overall provider status;
- active warnings;
- last sync time.

Example:

```text
Today
$12.40 / $50.00
$37.60 remaining
24% used

Week
$71.30 / $250.00
Projected: $228.00
Status: OK
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

Each provider account should show:

- provider name;
- account/workspace display name;
- masked credential reference;
- connection status;
- last successful sync;
- last error;
- configured budgets;
- supported metrics for that provider.

### Settings

Settings should include:

- global minimum polling interval;
- per-provider enable/disable;
- budgets and warning thresholds;
- local-only diagnostics export;
- data deletion;
- legal disclaimer;
- open-source license information.

---

## 10. Wear OS app scope

The Wear OS app is a compact dashboard, not a full settings app.

It should be built with Kotlin and Compose for Wear OS.

### MVP screens

```text
Today
Week
Providers
Alerts
Last sync
```

The implemented app additionally has a Usage screen for plan and purchased allowances.
Phase 13 replaces the home screen with configurable percent rings while keeping per-metric
detail screens.

### Today screen

```text
Today
$12.40 / $50
24% used
$37.60 left
OK
```

### Week screen

```text
Week
$71 / $250
Projected $228
Normal
```

### Providers screen

```text
Codex   $8.10 OK
Claude  $2.80 OK
Cursor  68%  Warn
```

### Alerts screen

```text
High burn rate
Codex usage is 2.1x normal
Updated 4m ago
```

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
available only in debug builds and must be enabled explicitly on the phone. Phase 13 plans
schema version 4, which replaces the preference-filtered allowance list with explicitly
selected ring entries.

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
connection rows in Settings instead.

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
- `platform`: organization/team usage and cost reporting, authenticated with an
  administrative API key.

One authorization per connection kind is unavoidable: for every provider the subscription data
and the organization reporting live behind different credentials and different endpoints. A
single provider section in Settings groups both connections; neither implies the other.

```text
Provider   Plan connection                          Platform connection
OpenAI     Codex device-code OAuth                  Admin API key
           /backend-api/wham/usage                  /v1/organization/usage/completions
           (compatibility, implemented)             /v1/organization/costs
                                                    (official, implemented)

Anthropic  Claude subscription OAuth                Admin API key
           GET /api/oauth/usage                     /v1/organizations/usage_report/messages
           utilization % per window + extra usage   /v1/organizations/cost_report
           (undocumented compatibility)             (official)

Cursor     Dashboard session endpoints              Team/org Admin API key
           GET /api/usage-summary                   POST /teams/daily-usage-data
           plan/on-demand percentages               (official, teams and enterprise only)
           (undocumented compatibility)
```

Key findings per provider:

- Anthropic mirrors OpenAI exactly. The official Usage & Cost Admin API returns token usage
  (1m/1h/1d buckets) and daily USD cost as decimal strings, requires an organization Admin API
  key, and is documented to support polling once per minute. The Claude subscription endpoint
  `GET /api/oauth/usage` is the same undocumented contract Claude Code's `/usage` command uses:
  it returns `five_hour`, `seven_day`, and per-model window utilization percentages with reset
  timestamps plus an `extra_usage` purchased-credit block, and requires the Claude Code OAuth
  token, the `anthropic-beta: oauth-2025-04-20` header, and a Claude Code user agent. Community
  monitors observe stable behavior at roughly 3-minute polling. This is a Codex-style
  compatibility integration and must degrade gracefully.
- Cursor has no official API for individual accounts. Personal plan usage exists only behind
  cookie-authenticated dashboard endpoints (`GET /api/usage-summary` and related POST
  endpoints), which report plan and on-demand usage as percentages of the billing cycle. The
  official Admin API covers teams and enterprise organizations only, uses Basic auth with a
  team API key, allows 20 requests per minute, aggregates data hourly, and documents polling at
  most once per hour. A Cursor plan connection is therefore the riskiest compatibility
  integration and needs explicit experimental framing.
- Codex-style plan data is percentage-first. All three plan connections can report usage as a
  percentage of a window or cycle, which is what compact surfaces (watch rings, summary cards)
  should standardize on.

Everything normalizes into the existing core model: plan windows and purchased balances map to
`AllowanceState`, platform reporting maps to `UsageBucket`/cost totals, and each connection gets
its own capability descriptor so the UI can adapt.

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
save a valid OpenAI Admin API key in Settings on an Android phone or emulator
refresh and confirm that OpenAI today/week/month cost plus usage/model data are rendered
confirm the saved key remains masked and no sensitive values appear in logcat
```

Codex subscription slice:

```text
phone owns Codex device-code sign-in, secure token storage, refresh, and read-only reporting
no desktop process, local server, or adb reverse dependency remains
Rust normalizes plan windows, purchased credits, and daily token buckets without fake money values
plan usage is displayed by default; users can select plan, purchased usage, or both
the same filtered allowance summary is propagated to Wear OS through schema version 3
Android end-to-end acceptance remains: sign in from Settings and verify the live phone/watch UI
```

### Phase 8 — MVP hardening

Status: in progress as of 2026-07-19; Phase 7 live acceptance remains pending.

Completed slice:

- the phone keeps the last successful live snapshot after a refresh failure;
- cached dashboard, provider, and watch-summary state is marked stale;
- the dashboard labels previous data explicitly while preserving its original timestamp;
- OpenAI authentication, permission, rate-limit, availability, and response failures surface as fixed safe messages;
- status icons expose concise tooltips, and credential entry can reveal only the current unsaved key on demand.

Deliverables:

- error states;
- empty states;
- offline states;
- stale data indicators;
- data deletion;
- privacy policy draft;
- legal disclaimer;
- source license scope review;
- trademark/brand asset notice review;
- paid Google Play distribution notes;
- Play Store internal testing build;
- real device smoke tests.

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

Status: planned as of 2026-07-24.

Rationale: Codex sign-in and the OpenAI Platform Admin key are one product relationship with
OpenAI, but Settings presents them as two unrelated rows. Research in section 15 shows every
provider follows the same dual shape, so Settings should group connections by provider.

Deliverables:

- one Settings section per provider: OpenAI, Anthropic, Cursor;
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
Settings shows one OpenAI section containing the Codex and Platform rows
an Admin API key can be saved with and without a custom label
the label appears in Settings and provider details instead of the generic title
removing a credential also removes its label
existing stored credentials survive the regrouping without re-entry
```

### Phase 10 — capability-adaptive dashboard

Status: planned as of 2026-07-24.

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

Status: planned as of 2026-07-24.

Rationale: automatic polling needs explicit per-provider cadence floors before it ships.
Reporting endpoints are rate-limited separately from model inference and agent traffic, so
frequent report polling never affects a running agent; the constants must document this.

Deliverables:

- named minimum-interval constants in `core/ward-pulse-providers`, one per connection kind,
  each with a comment linking its source (see section 14);
- a `const fn` lookup beside `provider_capabilities` returning the minimum poll interval and
  freshness guidance for a provider connection;
- one global refresh interval setting rendered as a slider from the strictest hard minimum
  (rounded up) to 60 minutes;
- a visible freshness note on Cursor connection rows in Settings explaining that Cursor
  aggregates usage data hourly, so refreshed values may lag behind actual activity;
- automatic background polling on the phone (WorkManager), honoring the slider and the
  per-connection clamp; this absorbs the "automatic provider polling" deliverable from
  Phase 8;
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

The strictest hard floor is 5 minutes, so the slider spans 5 to 60 minutes. Cursor aggregates
usage data hourly on the provider side; instead of clamping Cursor to an hourly cadence, the
Cursor connection rows in Settings carry a visible note that Cursor refreshes this data
infrequently, so faster polling may keep returning the same values.

Acceptance:

```text
constants exist with doc-linked comments and unit tests
the slider persists and background sync honors it
each connection never syncs faster than its floor
a 429 response still slows the affected provider without blocking others
```

### Phase 12 — Anthropic and Cursor adapters on the connection model

Status: planned as of 2026-07-24.

Rationale: the section 15 research shows both remaining providers fit the plan/platform split
already proven by Codex plus OpenAI Platform. Anthropic goes first because both of its
connections have stable, well-understood contracts.

Deliverables:

- Anthropic platform reporting: Admin API key transport for
  `/v1/organizations/usage_report/messages` (daily buckets for the dashboard; hourly available)
  and `/v1/organizations/cost_report` (daily buckets only, USD as decimal-string cents), with
  pagination, Rust normalization, a capability descriptor, and sanitized fixtures;
- Claude subscription: OAuth token per the Claude Code contract, `GET /api/oauth/usage`
  normalization of window utilization percentages, reset timestamps, and extra-usage credits
  into `AllowanceState`; explicitly a compatibility integration that degrades gracefully like
  Codex;
- Cursor plan usage: session-authenticated dashboard endpoints normalized into plan and
  on-demand allowances; framed as experimental, with the sign-in flow owned by the phone and
  the session token in secure storage;
- Cursor platform reporting: team Admin API key support for users who administer a team,
  with the Settings freshness note from Phase 11 on both Cursor connection rows;
- capability descriptors registered for `ProviderKind::Claude` and `ProviderKind::Cursor`;
- `docs/product/PROVIDER_NOTES.md` updated per provider with credential type, permissions,
  rate limits, revocation path, and redaction rules.

Acceptance:

```text
each new connection can be added, synced, and removed from its provider section
plan percentages and purchased balances render through the existing allowance cards
sanitized fixtures cover every new parser
a failing connection leaves other providers' data visible
no tokens, cookies, or raw payloads appear in logs
```

### Phase 13 — configurable watch rings

Status: planned as of 2026-07-24.

Rationale: watch space is limited and must never show `Unknown` filler. Plan data from all
three providers is percentage-first, so the watch surfaces should standardize on compact
percent rings. This is primarily a design task and starts in OpenPencil before any code.

Deliverables:

- OpenPencil design sources under `apps/watchface_wff/design/` and `apps/wear_android/design/`
  covering 1-4 ring layouts on round and square faces plus ambient mode, following
  `docs/DESIGN_ASSETS.md` ownership rules;
- a ring binds to exactly one metric: a provider plan window percent, a purchased/credit
  percent, or a local budget percent, colored by status;
- a "Watch display" section in phone Settings selects up to four ring slots; metrics from
  unconnected providers are visible but disabled (grayed) with the same `?` explanation
  affordance as the dashboard;
- unselected and unavailable metrics simply do not render on the watch: no placeholders;
- no time-based rotation of providers in the first iteration: simultaneous static rings are
  battery-safe and fit WFF's declarative model, while rotation would require animation or
  frequent updates; rotation may be revisited later with explicit power measurement;
- watch summary schema version 4: an ordered list of selected ring entries (stable id, short
  label, percent, status) that still excludes credentials, account ids, and raw provider data;
- ring selection supersedes the version 3 plan/purchased preference filter for the watch
  payload; the plan/purchased preference keeps filtering the phone dashboard only;
- the Wear OS home screen renders the same rings with per-ring detail screens;
- the WFF face renders up to the supported number of ring arcs with tap-to-open preserved.

Acceptance:

```text
ring layout designs are exported and reviewed before implementation starts
schema version 4 validates and sanitized fixtures are updated
watch face and Wear app show only configured rings
disabling a provider or ring on the phone removes it from the watch after the next sync
ambient mode stays readable with rings visible
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
```

Release CI can be added later:

```text
release-android.yml
  build signed phone AAB
  build signed wear AAB
  build signed watch face AAB
  upload artifacts
```

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

Complete Android end-to-end acceptance for on-device Codex reporting: connect the Codex account
from phone Settings, then verify plan usage and token activity on the phone and watch.

After that, start Phase 9 (provider-grouped connections) followed by Phase 10
(capability-adaptive dashboard): together they remove the "Unknown" placeholder wall for
single-connection setups and merge the Codex and OpenAI Platform rows into one OpenAI section.
Phase 11 then makes polling cadence explicit before Phase 12 adds Anthropic and Cursor, and
Phase 13 redesigns the watch surfaces around configurable percent rings, starting in
OpenPencil.

Phase 6 passed Watch Face Format acceptance on 2026-07-19:

```text
the resource-only WFF v1 package built as APK and AAB without dex files
the package installed and rendered on the canonical round Wear OS 6.1 emulator
the static today/week/status layout remained separate from live application state
tapping the face opened app.wardpulse/.wear.MainActivity
ambient mode rendered a readable thin time layer with a minimal product label
pull-request CI now validates, lints, and builds the watch face package
```

The OpenAI Platform organization reporting adapter, secure credential boundary, pagination,
retry handling, redacted outcome logging, deterministic Rust normalization, and automated
tests are implemented. Direct Codex rate-limit and token-activity reads have passed against the
current backend contract; the phone sign-in and Wear OS presentation still need emulator
acceptance.
