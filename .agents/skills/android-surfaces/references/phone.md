# Phone app rules

Required for all phone-shell work routed by [android-surfaces](../SKILL.md), including
UI, widgets, credentials, settings, repositories, Rust snapshot consumption,
background sync, transport, storage, diagnostics and build work.

- Own provider setup, credential entry, secure storage integration, platform transport, sync scheduling, diagnostics export, and Wear Data Layer send.
- **Dashboard status marks** follow `docs/product/PHONE_DASHBOARD_DESIGN.md` (**rules locked
  2026-08-13**): `Ok` draws nothing; a rollup counts the problems rendered below it and shows a
  count where a leaf shows a glyph; family color stays
  identity; rank from `ProviderStatus::severity`, never a new list.
- Consume dashboard snapshots from Rust.
- **2026-11-01 Fable metric accent:** only Claude Plan `claude-seven-day-fable` and widget
  ring ID `allowance.claude.claude-seven-day-fable` use approved `#FF603D` (warm red with
  an orange tint), before family fallbacks.
  Ordinary Claude stays `#E8915A`; labels, legacy windows, budgets and status chrome do not
  select the accent. Preserve unknown versus zero, six independent widget rows, credits
  and real optional resets. Native/public acceptance remains Pending for HOST.
- **2026-11-01 watch selection:** offer `Claude plan` and `Claude · Fable` independently;
  pair ordinary Claude inside/left and Fable outside/right only when both known halves are
  selected. Keep meaningful window subtitles and rank the band by its tighter half.
  Reuse local capacity validation for catalogue-order default admission, additions and
  publication: three bands, at most two completed pairs. Semantic migration/deduplication
  must not capacity-trim explicit choices. Preserve null defaults, explicit empty and valid
  saved selections. Invalid saved combinations stay visible with distinct band/split reasons;
  selected unavailable/missing choices remain removable through partial correction. Reject
  invalid additions without saving. Validate the full saved IDs before filtering or encoding;
  retain the last published watch summary until corrected. Provider polling, Dashboard and
  widget updates remain independent; six expanded widget rows have no watch capacity rule.
- Show today, week, month, provider plaques on Dashboard, charts, budgets, credits, sync
  status, Providers connection hub, and Settings.
- Phase 14 primary tabs: Dashboard → Watchface → Widget → Providers → Settings. Watchface owns
  Wear/WFF ring-slot prefs; Widget owns phone home-widget prefs and the Android App Widget
  (`PHONE_WIDGET_DESIGN.md`, revised 2026-11-03). Preserve the full launcher allocation
  and tap area while centering an intrinsic card inside a transparent root. The existing
  background and decorative layers live in the inner card; STALE and mark share one
  nominal 19dp header. Native metrics determine width, full rows and bottom padding.
  Keep six independent selections, stable IDs/migrations, explicit empty/default meaning,
  expanded windows, the current comparator, exhausted zero and separate purchased credits.
  Widget-local known-spend budgets need no cap; saved supported unknown budgets remain
  unavailable rows, while unsupported/missing saved choices stay removable without fake rows.
  Preserve shared Watch eligibility and F05. Carry exact Money minor-unit/currency and
  independent Extra used/applicable-cap Quantity strings through the private cache, clearing
  absent/removed fields and preserving legacy decoding when the discriminator is absent.
  Distinguish no cap, unusable cap, missing spend, percentage unavailable and missing Quantity.
  Render complete Money with reported currency/sign/cents at 30 Bold; exhaust released
  whole-column width before 26 Bold, never 18, clipping, ellipsis or an 84-unit refusal.
  Keep budget spent/cap at 18 Bold/11 Regular; Extra uses one 18 Bold used/cap line, with
  independent missing amounts and actual units; purchased balances remain 26 Bold.
  Use exact bundled Noto through the existing bounded native painter, glyph checks,
  4096-side/platform-or-8MiB limits and at most two variants. Preserve whole-column fallback,
  trailing-row fallback only for height/memory, complete empty/no-fit text at 12 Regular,
  and accessibility-only fallback when copy cannot fit. Never hide width-unfit Money by
  dropping selected rows. Measure complete right details and reset footprints; retain real
  selected-allowance UTC resets below their own right balance, device-local English
  `Reset DD MMM HH:mm` and timezone redraw. Invent no budget/sibling reset or as-of.
  Accessibility keeps full identity and only visible values/details/reset, distinguishing
  spend, remaining purchased credits and Extra Credits used/cap. Preserve publication,
  coalescing and cold/warm Dashboard taps. Generator-owned widget/picker exports and named
  guides travel with the correction; historical art and dated evidence remain protected.
  Illustrative USD/UTC art is not provider/native/alpha proof; HOST acceptance stays pending.
  Watchface collapses ordinary Claude windows, choosing the tightest known window including
  zero, while Fable stays separately selectable and pairs only when both halves are selected;
  exhausted selected watch metrics remain visible after the 2026-10-13 revision. Do not keep
  those controls in Settings.
- **Providers** owns the full connection catalog (Connected / Not connected), credentials /
  auth, and **all user-configured** alert thresholds: connection-local Plan defaults,
  normalized Plan-window overrides and Purchased on plan rows; Today/Week/Month on reporting
  rows. Missing overrides inherit Plan; explicit Off stays distinct. Shared editors accept
  presets and custom whole **0–100% left** (storage/Rust keep used% as `at`). Reported windows,
  including unknown usage, are independent of watch selection. General Plan/Purchased and
  budget settings remain editable before first sync; actual windows require a report.
  Do not keep alert rules under Settings.
- **Settings** is systemic only: global polling interval, diagnostics, data deletion,
  legal, debug toggles — not connections, credentials, display surface toggles, or alerts.
- Do not add a phone Alerts tab. Active alerts render on the Dashboard. Thresholds are
  **user-configured only** — never invent alerts from hard-coded 80%/100% utilization cutoffs.
  Provider status chrome (Warning / RateLimited) is separate from the alerts list.
- Keep analytics UI dense, clear, and operational rather than marketing-like.
