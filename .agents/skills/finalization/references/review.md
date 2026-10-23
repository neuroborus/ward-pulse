# Finalization review checklists

Complete these sections through [finalization](../SKILL.md).

## 1. Scope Review

- [ ] Changes match the current product phase in `docs/DEVELOPMENT_PLAN.md`.
- [ ] Root files stay short and operational; durable requirements stay under `docs/`.
- [ ] No generated platform project noise was added unless the user asked for it.
- [ ] No unrelated local or user changes were reverted.
- [ ] Changed OpenPencil sources and their generated runtime exports are staged together.
- [ ] Changes follow root `AGENTS.md` working agreements.

## 2. Boundary Review

- [ ] Rust domain logic stays under `core/`.
- [ ] Provider normalization stays in Rust; platform transport and credential storage stay in app shells.
- [ ] Flutter phone work stays in `apps/phone_flutter/`.
- [ ] Wear OS Kotlin/Compose work stays in `apps/wear_android/`.
- [ ] Watch Face Format resources stay in `apps/watchface_wff/`.
- [ ] Generated bindings stay in `bindings/*/generated/`; source interface design stays in `core/ward-pulse-ffi/`.
- [ ] Shared contracts stay in `schemas/`; sanitized examples stay in `fixtures/`.

## 3. Security Review

- [ ] No provider credentials, authorization headers, raw prompts, or sensitive raw provider payloads entered the change set.
- [ ] Logs, fixtures, examples, and docs use redacted or mock data.
- [ ] Credential rules in `docs/product/SECURITY_MODEL.md` still match implementation assumptions.
- [ ] Wear OS and watch face surfaces do not gain credential entry or credential storage responsibilities.

## 6. Documentation Review

- [ ] `docs/README.md` links any new durable document.
- [ ] The Vocs page and `docs/site/vocs.config.ts` navigation are updated for documentation exposed on the site.
- [ ] Vocs pages import authoritative Markdown instead of duplicating it.
- [ ] Root README begins with current product guidance, the approved PNG gallery and a user-guide entry.
- [ ] Apply [user-docs](../../user-docs/SKILL.md) to public pages, routes and screenshots; refresh
      affected UI PNGs and their index, and keep developer/internal documentation out of the public site.
- [ ] Apply [docs-gate](../../docs-gate/SKILL.md#keep-documentation-current) to reconcile affected
      documentation in this change set, or justify no documentation impact in the handoff.
- [ ] Placeholder TODOs are acceptable only for intentionally deferred platform generation work.
