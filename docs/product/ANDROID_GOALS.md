# Android Goals

WardPulse starts as an Android ecosystem product with these surfaces:

- Phone app: primary dashboard, provider setup, credentials, budgets, charts, sync state, and settings.
  Phase 14 primary tabs: Dashboard → Watchface → Widget → Providers → Settings. Watchface and
  Widget configure glance surfaces; Settings does not (until then, ring slots may still live
  under Settings “Watch display”). No phone Alerts tab — active alerts on Dashboard; alert
  rules / thresholds in Settings on connection rows (independent of current sync).
- Phone home-screen widget (planned, Phase 14): configurable glanceable summary with its own
  visual language — not a copy of the watch face; configured on the Widget tab, independently
  of Watchface.
- Wear OS app: compact dashboard for today, week, providers, alerts (active list only), and last sync.
- Watch Face Format package: glanceable concentric remaining rings and fast launch into the Wear OS app.

## MVP Goals

- Build a local-first dashboard around AI tool usage, spend, limits, credits, and provider status.
- Keep credentials on user devices.
- Normalize provider-specific reporting into shared Rust-owned models.
- Support mock data first, then one real provider.
- Share schemas, fixtures, tests, and release process across surfaces.

## MVP Non-Goals

- Cloud account system.
- Cloud-stored provider credentials.
- Payment or subscription implementation.
- Custom provider plugin marketplace.
- Real-time agent tracking unless a provider offers a clear API.
- iOS, watchOS, or visionOS implementation.
