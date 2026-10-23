# @wardpulse/app

## 0.1.0

### Minor Changes

- Introduce WardPulse, a local-first Android usage dashboard backed by a shared Rust core. Report OpenAI API, Anthropic organization and Cursor Enterprise usage, with experimental Codex, Claude and Cursor plan connections. Group connections by provider and show available usage, spend, credits, plan windows, model breakdowns and history.
  Add per-connection budgets and alert thresholds, optional plan-recovery notifications, configurable polling and manual refresh. Persist last successful connection data for foreground and background sync, marking recovered data stale. Keep credentials encrypted on the phone and send only compact credential-free summaries to the watch.
  Add optional Wear OS Glance, plan-window and alert views, complications, and configurable Watch Face Format rings with editable upper cells. Include legacy and bundled Watch Face Push packages and a configurable phone home-screen widget.
  Link phone Settings to public setup and troubleshooting guides, including provider, sync and privacy guidance, and identify WardPulse as an independent product.
  Implement signed Android bundle/installer builds and an independent manual Google Play preparation/apply workflow in source. Local preparation and generated notes do not establish hosted publication, Play delivery or remaining device acceptance.

### Patch Changes

- 46a2af2: Add Changesets release preparation with repository-wide coverage auditing and guarded Android version updates. Let manual GitHub releases use prepared Changesets notes and select draft, prerelease and latest state, verifying signed artifact transfers before publication.
