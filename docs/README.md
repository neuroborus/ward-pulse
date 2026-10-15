# WardPulse Docs

This directory is the repository documentation index and gate. Root README introduces the
product, screenshots and user guide; durable product and engineering knowledge lives here.
The public Vocs site presents user guidance, the product roadmap and privacy/help.
Contributor and technical references below remain available in the repository without
becoming public Vocs pages.

## User Guide

- [Getting started](product/user-guide/GETTING_STARTED.md)
- [Connect providers](product/user-guide/PROVIDERS.md)
- [Read the Dashboard](product/user-guide/DASHBOARD.md)
- [Watch and watch face](product/user-guide/WATCH.md)
- [Home widget](product/user-guide/WIDGET.md)
- [Sync and notifications](product/user-guide/SYNC.md)
- [Settings and privacy](product/user-guide/SETTINGS.md)
- [Troubleshooting](product/user-guide/TROUBLESHOOTING.md)
- [Report an issue](product/user-guide/REPORT_AN_ISSUE.md)
- [Roadmap](product/user-guide/ROADMAP.md)
- [UI screenshot index](assets/README.md)

## Start Here

- [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) is the full product and implementation plan.
- [ANDROID_TOOLCHAIN.md](ANDROID_TOOLCHAIN.md) records the verified Android/Flutter development baseline, SDK package names, AVDs, and setup commands.
- [DESIGN_ASSETS.md](DESIGN_ASSETS.md) defines OpenPencil source ownership and runtime export workflow.
- [product/WATCH_RING_DESIGN.md](product/WATCH_RING_DESIGN.md) — **baseline locked 2026-07-25**
  (melt/strip-accent revision **2026-07-27**): Wear / WFF concentric remaining rings, clockwise
  melt from 12, sunk ColorRamp strips, provider colors.
- [product/PHONE_WIDGET_DESIGN.md](product/PHONE_WIDGET_DESIGN.md) — **locked 2026-07-27**:
  phone home-widget rows that fit the resized widget, up to six selected metrics, App Widget surface.
- [product/WEAR_GLANCE_DESIGN.md](product/WEAR_GLANCE_DESIGN.md) — **baseline locked 2026-07-26**: Wear app Glance text legend (OK/!OK refresh, cadence vs rate-limit, Alerts pill); not a face clone.
- [product/PHONE_DASHBOARD_DESIGN.md](product/PHONE_DASHBOARD_DESIGN.md) — **status rules locked
  2026-08-13**: when a status mark appears on the phone Dashboard and how a rollup differs from a
  leaf. Rules, not a composition — no review board.
- [DOCUMENTATION.md](DOCUMENTATION.md) defines documentation ownership, Vocs tooling, and contributor workflow.
- [product/ANDROID_GOALS.md](product/ANDROID_GOALS.md) defines the MVP goal, surfaces, and non-goals.
- [product/PROVIDER_NOTES.md](product/PROVIDER_NOTES.md) tracks provider integration assumptions and open questions.
- [product/SECURITY_MODEL.md](product/SECURITY_MODEL.md) defines local-first credential and diagnostics rules.
- [product/PRIVACY_POLICY.md](product/PRIVACY_POLICY.md) is the public privacy policy for the Android product.
- [product/RELEASE_CHECKLIST.md](product/RELEASE_CHECKLIST.md) is the release readiness gate for phone, Wear OS, and watch face builds.
- [../LICENSE](../LICENSE), [../TRADEMARKS.md](../TRADEMARKS.md), [../THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md), and [../brand/README.md](../brand/README.md) define the source license, attribution gate, and brand boundaries.

## Project Gates

Use this index before adding new work:

1. Product scope belongs in `docs/product/`.
2. Stable cross-platform data contracts belong in `schemas/`.
3. Portable business logic belongs in `core/`.
4. Platform-specific UI, transport, storage, and background execution belong in `apps/`.
5. Generated bindings belong in `bindings/*/generated/`; source interfaces belong in `core/ward-pulse-ffi/`.
6. Sanitized examples belong in `fixtures/`; secrets, raw prompts, auth headers, and sensitive provider payloads must not be committed.
7. Shared product-identity OpenPencil sources belong in `brand/`; app-specific design sources stay with their owner.
8. Apache-2.0 source rights and brand rights stay separate.

## Documentation Rules

- Keep root README short and product-first, with an early screenshot gallery and user-guide
  entry; place the contributor link at the end and keep developer commands with their owners.
- Keep long requirements and decisions in this folder.
- Update `DEVELOPMENT_PLAN.md` when current scope, status, open work or verified acceptance changes.
- Add focused documents instead of growing one catch-all file.
- Link new documents from this index before relying on them in implementation.
- Add a thin page under `site/src/pages/` and update `site/vocs.config.ts` only for public user
  guidance, the product roadmap and relevant privacy/help; apply
  [user-docs](../.agents/skills/user-docs/SKILL.md).
- Run `just check-docs` after changing durable docs, Vocs pages, or navigation.
- Cite source files by named symbols or recipes instead of line numbers; the checkout-only
  gate is `just check-doc-citations` (see [DOCUMENTATION.md](DOCUMENTATION.md)).
