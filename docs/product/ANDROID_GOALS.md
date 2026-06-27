# Android Goals

WardPulse starts as an Android ecosystem product with three surfaces:

- Phone app: primary dashboard, provider setup, credentials, budgets, charts, sync state, and settings.
- Wear OS app: compact dashboard for today, week, providers, alerts, and last sync.
- Watch Face Format package: glanceable summary and fast launch into the Wear OS app.

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
