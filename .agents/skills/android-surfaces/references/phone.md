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
  ring ID `allowance.claude.claude-seven-day-fable` use `#FF8A00`, before family fallbacks.
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
  (`PHONE_WIDGET_DESIGN.md`, revised 2026-11-01). The phone widget fills the actual
  launcher allocation and centers compact complete rows/columns, up to six selections.
  Keep expanded Claude/Codex windows, stable IDs/migrations, tightest-first ordering,
  exhausted `0%`, unavailable omission and finite purchased-credit eligibility.
  Render every visible string with the exact bundled Noto Regular/Bold through the bounded
  native bitmap route (30/26/18/16/11 hierarchy; 12 Regular for complete empty/no-fit copy),
  independent of fontScale, system family and force-bold. Measure actual glyphs; omit a reset
  that crowds a valid balance, then whole detail and label columns by width and trailing
  rows by height. Preserve two-line family/pool names, including Cursor/Models; never
  ellipsize, shrink typography, substitute a system face or mutate host-owned options.
  Keep the quiet mark clear; stale fitting and painting share the measured 11 Bold padded
  line plus 2dp. Exceptionally tiny hosts retain an accessible fallback without clipped text.
  Carry only the selected allowance's real optional reset through the phone-private cache;
  clear absent/removed fields and safely retain old flat-label caches. Use device-local
  English `Reset DD MMM HH:mm`, with no inferred budget reset, ticker or fabricated rollover.
  Keep one root accessibility summary with full identity for every visible row, omit hidden
  rows and announce purchased/reset meaning only when displayed. Keep the image decorative
  and preserve cold/warm Dashboard tap/readiness behavior. Descriptive Widget-tab language,
  credentials, fetching and phone-watch transport stay with their existing owners.
  Regenerate review/picker art through `tools/render-phone-widget-designs.mjs`; illustrative
  values and former-renderer captures are not replacement native acceptance.
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
