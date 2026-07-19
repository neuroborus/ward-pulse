---
name: docs-gate
description: WardPulse documentation, schema, fixture, and planning gate. Use when updating docs, adding requirements, changing project scope, editing schemas, adding fixtures, creating release/security/provider guidance, or deciding whether a change belongs in README, docs/product, schemas, fixtures, or tools.
---

# Docs Gate — WardPulse

Use this skill before changing durable project knowledge.

## Placement

- Root `README.md`: short project orientation, repository shape, command entry point.
- Root `AGENTS.md`: short working agreements for agents and humans.
- Root `LICENSE`, `TRADEMARKS.md`, and `THIRD_PARTY_NOTICES.md`: Apache-2.0 source license, brand usage, and attribution gate.
- `docs/README.md`: index and gate for project documentation.
- `docs/DOCUMENTATION.md`: documentation ownership, Vocs tooling, and contributor workflow.
- `docs/site/`: Vocs configuration, navigation, and thin presentation pages.
- `docs/DEVELOPMENT_PLAN.md`: full product and implementation plan.
- `docs/product/ANDROID_GOALS.md`: Android MVP goals and non-goals.
- `docs/product/PROVIDER_NOTES.md`: provider integration assumptions and open questions.
- `docs/product/SECURITY_MODEL.md`: local-first credential, logging, and diagnostics rules.
- `docs/product/RELEASE_CHECKLIST.md`: release readiness gate.
- `schemas/`: stable cross-platform data contracts.
- `fixtures/`: sanitized provider and dashboard examples.
- `brand/`: product identity assets that are not open source by default.

## Rules

- Link new durable docs from `docs/README.md`.
- Keep authoritative prose in `docs/` or beside its owning component; Vocs pages should import it instead of copying it.
- Update `docs/site/vocs.config.ts` when an exposed document is added, removed, or renamed.
- Keep root docs concise; move detailed requirements into `docs/`.
- Keep root `AGENTS.md` aligned with `.agents/skills/*` when workflow checks or ownership boundaries change.
- Keep Apache-2.0 source licensing and WardPulse brand rights separate.
- Keep schemas aligned with Rust models when a contract becomes stable.
- Prefer closed JSON contracts with explicit nullable fields and `additionalProperties: false`.
- Keep fixtures sanitized: no secrets, raw prompts, authorization headers, or sensitive raw provider payloads.
- Update security docs when credential handling, logging, diagnostics, or provider payload handling changes.
- Update provider notes when adding a new provider, endpoint assumption, capability descriptor, or rate-limit rule.

## Review Questions

- Is this information operational, product, security, provider, release, schema, or fixture knowledge?
- Is it duplicated somewhere else?
- Will another agent know where to find it from `docs/README.md`?
- Is the Vocs page and navigation current when this document is exposed on the site?
- Does this change alter phase scope in `docs/DEVELOPMENT_PLAN.md`?
- Does this create a public contract that should be represented in `schemas/`?
