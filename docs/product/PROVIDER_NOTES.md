# Provider Notes

Provider integrations should be added one at a time. The initial implementation should use deterministic mock fixtures before connecting to live APIs.

## Initial Order

1. Mock provider.
2. OpenAI / Codex, if usage and cost reporting is available for the target account type.
3. Claude.
4. Cursor.

The order can change when API access, account type, or reporting endpoints make another provider a better first real integration.

## Integration Contract

Each provider should document:

- credential type and minimum required permissions;
- whether read-only analytics credentials are available;
- whether the credential can initiate billable actions;
- rate limits and polling guidance;
- available metrics: cost, tokens, requests, credits, daily buckets, hourly buckets, model breakdown, workspace breakdown;
- provider-side spending limit support;
- revocation path;
- redaction requirements.

## Boundary

Platform code owns transport, TLS, background scheduling, secure credential retrieval, retries, and encrypted storage. Rust owns parsing, validation, normalization, error mapping, aggregation, budgets, projections, alerts, and dashboard view models.
