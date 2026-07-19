# Provider Notes

Provider integrations should be added one at a time. The initial implementation should use deterministic mock fixtures before connecting to live APIs.

## Initial Order

1. Mock provider.
2. OpenAI, including Codex usage if OpenAI reporting exposes it for the target account type.
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

## OpenAI Platform organization reporting

Status: selected as the first live provider contract on 2026-07-19.

Scope:

- Target OpenAI Platform organization usage and cost reporting. Do not assume that this API includes personal ChatGPT or Codex subscription usage.
- Use an organization Admin API key with access to both reporting endpoints. Their published API contract requires `AdminApiKeyAuth`; an ordinary project API key configured as read-only is not sufficient. Treat the key as a privileged administrative secret and store it only in phone-secure storage.
- Send `GET` requests only. The key cannot call non-administration endpoints or run model inference, so this adapter cannot initiate billable model work; unrelated administrative privileges may still be present.
- Fetch completions usage from `GET /v1/organization/usage/completions` and cost from `GET /v1/organization/costs`.
- Request daily buckets for dashboard cost. Usage also supports hourly buckets and grouping by model, project, or user; cost supports daily buckets and grouping by project, line item, or API key.
- Follow response pagination. Phase 7 syncs on app start and manual refresh; automatic polling is deferred to MVP hardening and must run no more than once every 15 minutes. After `429`, honor `Retry-After` when present and apply exponential backoff with jitter.
- Keep budgets local. This adapter reads reporting data and does not manage provider-side spending limits or spend alerts.
- Never log the key, authorization header, full account identifiers, or raw response bodies.

Capabilities:

| Metric | Support | Notes |
| --- | --- | --- |
| Cost | Yes | Daily buckets from the Costs API. |
| Tokens and requests | Yes | Completions usage supports both. |
| Credits | No | No credit-grant reporting endpoint is part of this adapter. |
| Daily usage buckets | Yes | Completions usage supports daily aggregation. |
| Hourly usage buckets | Yes | Completions usage supports hourly aggregation. |
| Daily cost buckets | Yes | The Costs API supports daily aggregation. |
| Hourly cost buckets | No | The Costs API supports daily aggregation only. |
| Usage model breakdown | Yes | Usage can group by model. |
| Cost model breakdown | No | Cost cannot group by model. |
| Workspace breakdown | No | Project and user grouping must not be presented as workspace reporting. |
| Active agents | No | Reporting data is not live agent state. |

Revocation is performed in OpenAI Admin API key settings. OpenAI RBAC exposes a `Usage` read permission, but the reporting endpoints still require Admin API key authentication. WardPulse must therefore describe the credential as an organization Admin API key rather than a project read-only key.

Implementation status as of 2026-07-19:

- The phone stores the key with platform-secure storage and never reads it back into the credential field.
- The credential field can reveal only the current unsaved value after an explicit user action; saved credentials remain masked.
- Android backup is disabled so encrypted values cannot be restored without their device-bound key.
- Usage and cost pages are fetched directly from the phone, then passed without credentials or authorization headers to the Rust normalization boundary.
- OpenAI API costs are normalized as USD. Raw page JSON crosses the Dart-to-Rust boundary as strings so decimal values remain exact; Rust sums exact values before rounding period totals to cents. Missing optional amount fields are ignored and an empty successful cost report is represented as zero spend.
- Sync diagnostics contain fixed outcome names only. Provider response bodies are processed in memory and are not logged.
- Authentication, permission, rate-limit, availability, and response-shape failures are mapped to fixed UI-safe messages without response bodies or credentials.
- Sanitized fixtures cover report parsing; live acceptance requires a user-supplied Admin API key.

Official references:

- [Administration overview](https://developers.openai.com/api/reference/administration/overview)
- [Organization completions usage](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/completions)
- [Organization costs](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs)
