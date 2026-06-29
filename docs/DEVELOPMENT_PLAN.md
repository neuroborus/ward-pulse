# WardPulse Android — Development Plan

Updated: 2026-06-27

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

- OpenAI, including Codex usage where OpenAI reporting exposes it;
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
      uniffi.toml

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
        src/main/java/...
        src/main/res/...
      data/
      ui/
      test/

    watchface_wff/
      build.gradle.kts
      src/main/AndroidManifest.xml
      src/main/res/raw/watchface.xml
      src/main/res/drawable/
      src/main/res/xml/

  bindings/
    dart/
      README.md
      generated/
      wrappers/

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
Send WatchSummary through Wear Data Layer
   ↓
Wear OS app stores latest snapshot
   ↓
Watch face reads summary/complication state
```

The Wear OS app may later support standalone mode, but this is not required for the MVP.

### MVP payload

```json
{
  "generatedAt": "2026-06-27T18:42:00Z",
  "overallStatus": "ok",
  "today": {
    "spent": "12.40",
    "limit": "50.00",
    "remaining": "37.60",
    "usedPercent": 24.8
  },
  "week": {
    "spent": "71.30",
    "limit": "250.00",
    "projectedTotal": "228.00",
    "usedPercent": 28.5
  },
  "providers": [
    { "name": "Codex", "main": "$8.10", "status": "ok" },
    { "name": "Claude", "main": "$2.80", "status": "ok" },
    { "name": "Cursor", "main": "68%", "status": "warning" }
  ],
  "alerts": [
    { "severity": "warning", "message": "Codex burn rate is higher than usual" }
  ]
}
```

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
effective_interval = max(user_setting, provider_minimum, app_safe_interval)
```

The app should support these global settings:

- 5 minutes;
- 15 minutes;
- 30 minutes;
- 60 minutes.

A 1-minute option can exist only for mock/dev builds or providers that explicitly tolerate it.

### Rate limit handling

The sync layer should support:

- per-provider throttling;
- exponential backoff;
- jitter;
- `Retry-After` handling where available;
- automatic slowdown after repeated 429 responses;
- visible stale/rate-limited states in the UI.

The dashboard must keep showing the previous successful snapshot when a sync fails.

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
1. OpenAI, including Codex usage where OpenAI reporting exposes it
2. Claude
3. Cursor
```

The exact order can change based on API access, account type, and available reporting endpoints.

### Phase 3: provider capability matrix

Each provider should have a capability descriptor:

```rust
struct ProviderCapabilities {
    supports_cost: bool,
    supports_tokens: bool,
    supports_requests: bool,
    supports_credits: bool,
    supports_daily_buckets: bool,
    supports_hourly_buckets: bool,
    supports_model_breakdown: bool,
    supports_workspace_breakdown: bool,
    supports_active_agents: bool,
}
```

The UI should hide or downgrade unavailable metrics instead of showing broken placeholders.

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
just gen-bindings
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

Deliverables:

- Kotlin Wear OS app;
- Today screen;
- Week screen;
- Providers screen;
- Alerts screen;
- local mock summary storage;
- Compose for Wear OS UI.

Acceptance:

```text
Wear app runs on emulator
screens are readable on round and square previews
stale data state is visible
mock summary is persisted locally
```

### Phase 5 — phone-to-watch sync

Deliverables:

- phone app sends WatchSummary to Wear OS app;
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

### Phase 8 — MVP hardening

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
  ./gradlew assembleDebug
  WFF validation when configured
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

Create the monorepo skeleton and implement Phase 1 with mock data.

The first useful pull request should contain:

```text
docs/DEVELOPMENT_PLAN.md
LICENSE / TRADEMARKS.md baseline
Rust workspace
mock provider fixtures
DashboardSnapshot model
budget calculation tests
CLI command that prints a dashboard snapshot
Flutter app stub that can later consume the snapshot
Wear app stub that can later consume WatchSummary
```

The product should earn complexity step by step. Start with a stable data model and convincing dashboard states before adding real providers or release infrastructure.
