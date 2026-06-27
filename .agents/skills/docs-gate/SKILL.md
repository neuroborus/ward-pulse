---
name: docs-gate
description: WardPulse documentation, schema, fixture, and planning gate. Use when updating docs, adding requirements, changing project scope, editing schemas, adding fixtures, creating release/security/provider guidance, or deciding whether a change belongs in README, docs/product, schemas, fixtures, or tools.
---

# Docs Gate — WardPulse

Use this skill before changing durable project knowledge.

## Placement

- Root `README.md`: short project orientation, repository shape, command entry point.
- Root `AGENTS.md`: short working agreements for agents and humans.
- `docs/README.md`: index and gate for project documentation.
- `docs/DEVELOPMENT_PLAN.md`: full product and implementation plan.
- `docs/product/ANDROID_GOALS.md`: Android MVP goals and non-goals.
- `docs/product/PROVIDER_NOTES.md`: provider integration assumptions and open questions.
- `docs/product/SECURITY_MODEL.md`: local-first credential, logging, and diagnostics rules.
- `docs/product/RELEASE_CHECKLIST.md`: release readiness gate.
- `schemas/`: stable cross-platform data contracts.
- `fixtures/`: sanitized provider and dashboard examples.

## Rules

- Link new durable docs from `docs/README.md`.
- Keep root docs concise; move detailed requirements into `docs/`.
- Keep root `AGENTS.md` aligned with `.agents/skills/*` when workflow checks or ownership boundaries change.
- Keep schemas aligned with Rust models when a contract becomes stable.
- Prefer closed JSON contracts with explicit nullable fields and `additionalProperties: false`.
- Keep fixtures sanitized: no secrets, raw prompts, authorization headers, or sensitive raw provider payloads.
- Update security docs when credential handling, logging, diagnostics, or provider payload handling changes.
- Update provider notes when adding a new provider, endpoint assumption, capability descriptor, or rate-limit rule.

## Review Questions

- Is this information operational, product, security, provider, release, schema, or fixture knowledge?
- Is it duplicated somewhere else?
- Will another agent know where to find it from `docs/README.md`?
- Does this change alter phase scope in `docs/DEVELOPMENT_PLAN.md`?
- Does this create a public contract that should be represented in `schemas/`?
