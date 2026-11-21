# @wardpulse/app

## 0.1.0

### Minor Changes

- Set custom whole-percent alerts for individual plan windows, Purchased allowances and spend periods with a usable local limit. Control Alert notifications separately from Plan recovery, keep tracking while notifications are muted without replaying past crossings, and show the configured threshold in each alert. Request Android notification permission and explain how to enable blocked delivery.
  Show the optional Claude Fable weekly quota with its own color, paired watch band and independent widget choice. Display reported monthly Extra usage and its optional cap separately from Console expenses, preserving partial reports without invented amounts, reset dates or plan-name exclusions.
  Fit phone widgets with bundled fonts, complete rows and responsive columns, leaving unused space transparent. Show genuine reset dates, pool identities, expenses, caps and Extra usage when space permits. Use compact currency amounts with exact accessible descriptions, and give expense amounts the same bold emphasis as purchased balances. Keep known expenses selectable without a cap and unavailable values explicit. Add a Widget summary in Settings.
  Adapt watch-face band widths to the selected count and preserve paired identities through reordering and count changes. Improve full, near-full and short arcs, enlarge the whole face, align active and ambient clocks, and add Auto/Celsius/Fahrenheit for built-in weather. Show upper-cell provider text when available, a numeric fallback for ranged values and properly colored monochrome icons. Report selections held by watch capacity accurately.
  Make Cursor plan sign-in recoverable through Retry, Cancel and Help while preserving a saved connection after a failed replacement. Give Models and Other Models distinct Dashboard progress colors.
  Include current-day Anthropic costs and aggregate Cursor extra-paid expenses into Today, Week and calendar Month without counting included usage as spend. Present reporting sources consistently with separate expense blocks, advisory caps, report times and honest zero, partial or unavailable data. Clarify the reporting keys and access needed for each connection.
  Recognize expired Claude refresh grants as a sign-in problem instead of an unsupported usage response. Remove only the matching expired session, preserve a newer sign-in and explain how to connect again.
  Play WardPulse's original click when Roadmap is opened from the documentation menu. Keep direct links and browser history navigation silent, and let navigation continue if audio cannot play.
- Introduce WardPulse, a local-first Android usage dashboard backed by a shared Rust core. Report OpenAI API, Anthropic organization and Cursor team Admin API usage, with experimental Codex, Claude and Cursor plan connections. Group connections by provider and show available usage, spend, credits, plan windows, model breakdowns and history.
  Add per-connection budgets and alert thresholds, optional plan-recovery notifications, configurable polling and manual refresh. Persist last successful connection data for foreground and background sync, marking recovered data stale. Keep credentials encrypted on the phone and send only compact credential-free summaries to the watch.
  Add optional Wear OS Glance, plan-window and alert views, complications, and configurable Watch Face Format rings with editable upper cells. Include legacy and bundled Watch Face Push packages and a configurable phone home-screen widget.
  Link phone Settings to public setup and troubleshooting guides, including provider, sync and privacy guidance, and identify WardPulse as an independent product.
  Implement signed Android bundle/installer builds and an independent manual Google Play preparation/apply workflow in source. Local preparation and generated notes do not establish hosted publication, Play delivery or remaining device acceptance.
- e172b95: Keep saved-connection rejection warnings on Dashboard. Tap X to dismiss a warning, or let
  WardPulse clear it automatically after saving a fresh report from a verified replacement for
  the same connection. Reconnecting alone, viewing cached data, restarting the app or removing
  the connection leaves the warning visible. Each warning opens the exact Providers connection
  while preserving current connection status and usage data.

### Patch Changes

- 02340c2: Keep plan recovery and alert notification history with the accepted connection so replacement
  credentials do not inherit another scope's recovery edges or suppressed crossings. Preserve
  same-account continuity, isolate persisted histories, and explain opaque-key rotation and
  legacy unbound-history limits.
  Cancel obsolete reset wakes after the same accepted connection's native start or matching
  account success has served the reset, while retaining its recovery history and stored reset
  evidence. Keep unknown or unserved wakes protected and preserve qualified live history during
  Mock cleanup.
- 8691920: Correct Anthropic organization reporting expense totals by adding exact reported costs before rounding each daily and period total to USD cents.
- 84bce75: Keep widget rows and values consistent during concurrent updates from phone engines.
- 2737799: Keep Claude plan sign-in usable after a failed authorization code. Instead of leaving the
  dialog stuck or retrying a spent attempt, it shows the error with Restart sign-in and Cancel.
  Restart sign-in begins a fresh authorization, and an existing connection stays in place until
  a new sign-in succeeds.
- d213941: Enlarge the Wear OS Glance legend with measured text fitting, complete wrapping and local scrolling for larger text. Hide its clock while retaining clocks on Plan windows, Alerts and watch-face setup, with independent paging, rotary and accessibility navigation.
  Avoid duplicate Glance layers on app re-entry and keep first-sync/no-summary views usable. Draw genuinely full Glance mini-rings continuously while preserving partial values. Name the exact selected Cursor pair “Cursor / Others”, retaining Claude / Fable and existing compatibility fallbacks.
- 9fe72bd: Allow Codex disconnect to retire the local connection when encrypted session material is
  unavailable but local removal remains independently available. Keep unconfirmed removal
  distinct from remaining cleanup and optional provider revocation.
- fff7754: Keep independent Watchface and Widget choices when several selections save automatically at once, with immediate selection feedback and recovery after a failed save.
- ea00719: Keep an idle Dashboard and its watch summary healthy when saved alert thresholds or budget limits have no connected account to evaluate. Preserve unavailable usage and genuine sync problems.
- 419035a: Keep failed credential activations closed when another connection saves local data, so
  restart recovery preserves the prior confirmed credential and explicit reconnect stays usable.
- e670be9: Hide the watch face's standalone purchased-credit row when every Watchface ring is deselected.
  Keep the credits-only fallback for default preferences and selected rings whose data is unavailable.
- fa7d5cd: Preserve fractional UTC report times so a late older refresh cannot replace newer data from
  the same second, including in cached data recovered after restart.
- f1b7b51: Keep small positive watch ring usage, such as USD 0.04 spent of a USD 100.00 budget, from being published to Wear as zero.
  Wear now treats such a budget or plan pool as partly used instead of untouched; true zero still reads as full.
- 25b5f96: Give direct phone, Wear OS and Wear OS 5+ watch-face APK downloads clear filenames while preserving technical bundle and Push names. Keep Play preparation and promotion compatible with older published filenames selected from immutable producer source.
- c371b98: Keep debug Mock data on the phone widget and watch when background sync runs. Background
  work now skips provider reads, publications, recovery, alerts and STALE marks while Mock data
  is on or its setting cannot be read, and stops if Mock is turned on mid-run. Release builds
  keep Live mode and never read the debug Mock setting.
- ead03af: Use the saved Watchface and Widget choices when headless sync publishes collected usage, including selections changed or cleared during a refresh. If a surface's selection cannot be read, keep its prior output while continuing the other surface and background bookkeeping.
- ff55812: Correct separate watch-face setup guidance to distinguish installed, missing and unavailable installation checks. Refresh the guidance on recheck, revisit and return from external installation, without requesting activation or changing the installed face.
- 950c0ee: Keep home-widget cards centered at their content size when launcher allocations differ from
  the planned size. Retain advertised foldable sizes and legacy orientation fallbacks, and
  share the existing bitmap allowance across complete variants before reducing content.
- 924d69a: Preserve known-zero purchased-credit balances on home-widget plan rows, including their freshness status, while continuing to omit missing balances.
- e4c4b2f: Enlarge watch-face legend labels and upper readings, and lift the clock and watermark to give the legend more room. Preserve all three cells' outward border fades and add a downward fade only to the two lateral borders, keeping ring and zero-value semantics.
- 977edbe: Keep known token history bars visible when other intervals lack token counts, without presenting their partial sum as a complete total.
- 9b2c23e: Use WardPulse's original click for Alert notifications and Plan recovery. On Android 8.0 and newer, this default applies only to newly created notification categories; existing sounds and silent settings are preserved.
- 1be5f89: Restrict Plan recovery notifications to Plan allowances so purchased meters cannot trigger them, including from remembered keys after a usage reset.
- a3690eb: Reconcile disconnected plan rows and usage summaries as soon as local removal commits,
  even if later cleanup fails. Report remaining cleanup separately, preserve healthy sibling
  connections, and keep older disconnect feedback from overriding a replacement sign-in.
  Bind Claude sign-in completion to its original credential store so replacing the store
  cannot clear replacement credentials or publish obsolete connection callbacks.
- 46a2af2: Add Changesets release preparation with repository-wide coverage auditing and guarded Android version updates. Let manual GitHub releases use prepared Changesets notes and select draft, prerelease and latest state, verifying signed artifact transfers before publication.
- 320476f: Keep accepted provider data and widget rows when older work finishes after a connection
  becomes active. Completed missing-credential reads now retain private ownership evidence,
  so obsolete partial reports and failures cannot replace newer combined data or mark it stale,
  while healthy sibling connections keep their cached reports.
- d394aa5: Keep saved Dashboard caps marked as configured while spend is unknown instead of showing Not set. Preserve connection and period isolation, reported currencies and unknown usage values.
- 87273a3: Keep Watch and home-widget stale markers on retained selected data when another connection refreshes. Calculate freshness separately for each surface's metrics and displayed credits, and keep fresh-only Watch selections free of unrelated aggregate stale markers.
- Keep saved preferences when a read fails. Recover automatic polling after the phone clock
  is set back and let fresh usage replace older cached data on the phone, watch and home widget.
  Show temporary network unavailability for Claude transport interruptions while keeping the
  saved session and prior usage. Show when selected ring data is unavailable in Wear OS Glance,
  and let the optional Status complication indicate stale data after expiry without another
  phone sync. Use the matching provider family name in platform budget alerts.
- 9be55bb: Share automatic polling admission across foreground and background engines, retain attempt
  spacing after failures and restarts, and defer reset wakes until eligible. Preserve cached
  timestamps and suppress new alerts or recovery evidence for skipped connections while keeping
  explicit refresh and connection checks available under their existing guards.
- 54b7155: Keep phone usage histories, model details, allowance cards and expense headings identifiable by their source while scrolling. Show canonical provider and connection names in Budget and Alerts dialogs even when saved labels match.
- 833f506: Reject invalid JSON constants and timestamps without timezones during shared fixture
  validation, so malformed inputs cannot pass the gate before reaching phone or watch readers.
- 9ac80c0: Defer plan recovery notifications until fresh reports show usable included capacity across
  the target's necessary allowances. Keep blocked targets and their requirements across app
  restarts, so a short-window reset cannot prematurely announce recovery while a necessary
  weekly allowance is exhausted or unknown. Preserve independent provider scopes and qualify
  reported main-Codex pairs and explicit-null singletons without treating paid credits as
  included-quota recovery.
- c6114af: Restore the centre-time tap to Glance while keeping upper complication taps local to their
  visible cells. Preserve existing assignments, visual mapping and provider-supplied tap actions.
