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
- Show today, week, month, provider plaques on Dashboard, charts, budgets, credits, sync
  status, Providers connection hub, and Settings.
- Phase 14 primary tabs: Dashboard → Watchface → Widget → Providers → Settings. Watchface owns
  Wear/WFF ring-slot prefs; Widget owns phone home-widget prefs and the Android App Widget
  (`PHONE_WIDGET_DESIGN.md` locked). Phone widget **hugs** complete rows/columns inside
  the resize cell (olive `wrap_content`; hide trailing rows and right-hand columns that
  would clip — credits → label → `%`; unused cell area is wallpaper until the user shrinks
  the span), vertical+horizontal resize (default ~3 cells), day/night chrome, overlay face
  watermark (no header band), expands Claude windows, keeps exhausted plan pools as
  `0% left`, and appends per-provider purchased credits end-aligned (label centered).
  Watchface still collapses Claude, choosing the tightest known window including zero;
  exhausted selected watch metrics remain visible after the 2026-10-13 revision. Do not keep
  those controls in Settings.
- **Providers** owns the full connection catalog (Connected / Not connected), credentials /
  auth, and **all user-configured** alert thresholds (plan/purchased per connection;
  Today/Week/Month budgets on OpenAI Platform). One threshold per meter; UI speaks
  **% left** (storage/Rust keep used% as `at`). Editable before first sync. Do not keep
  alert rules under Settings.
- **Settings** is systemic only: global polling interval, diagnostics, data deletion,
  legal, debug toggles — not connections, credentials, display surface toggles, or alerts.
- Do not add a phone Alerts tab. Active alerts render on the Dashboard. Thresholds are
  **user-configured only** — never invent alerts from hard-coded 80%/100% utilization cutoffs.
  Provider status chrome (Warning / RateLimited) is separate from the alerts list.
- Keep analytics UI dense, clear, and operational rather than marketing-like.
