---
name: project-structure
description: WardPulse monorepo structure and ownership guidance. Use when creating, moving, or reviewing files and directories, adding modules, deciding where code belongs, or aligning implementation with the Rust core, Flutter phone, Wear OS, WFF, schemas, fixtures, bindings, tools, and docs layout.
---

# Project Structure — WardPulse

Use this skill before adding or moving project files.

## Source Of Truth

- Read `docs/README.md` for the documentation gate.
- Read `docs/DOCUMENTATION.md` when the change affects the Vocs site or documentation workflow.
- Read `docs/DESIGN_ASSETS.md` when the change affects editable or exported visual assets.
- Read `docs/DEVELOPMENT_PLAN.md` when the change affects architecture, product scope, or phase sequencing.
- Read root `AGENTS.md` for repository-wide working agreements.
- Keep the root clean: `README.md`, `justfile`, repository config, and short operational files only.

## Ownership Map

- `core/ward-pulse-core/`: stable product models, dashboard snapshots, budgets, alerts, projections, deterministic logic.
- `core/ward-pulse-providers/`: provider response parsing and normalization.
- `core/ward-pulse-ffi/`: source-of-truth platform interface.
- `core/ward-pulse-cli/`: local development and fixture/debug commands.
- `apps/phone_flutter/`: phone UI, provider setup, platform transport, secure storage integration, sync scheduling, Wear Data Layer sender.
- `apps/wear_android/`: compact Wear OS UI, Wear Data Layer receiver, local summary storage.
- `apps/watchface_wff/`: WFF XML/resources and tap-to-open behavior.
- `schemas/`: shared JSON contracts.
- `fixtures/`: sanitized provider and dashboard examples.
- `bindings/`: generated bindings and thin platform wrappers.
- `brand/`: protected product identity, shared OpenPencil sources, and store artwork placeholders.
- `tools/`: repeatable local automation.
- `docs/product/`: durable product, provider, security, and release guidance.
- `docs/site/`: Vocs workspace, navigation, and thin pages that present authoritative Markdown.

## Rules

- Do not make Rust depend on Flutter, Android, Google Play APIs, or platform credential storage.
- Do not make platform apps own shared product math or provider normalization.
- Do not put long product requirements in root files.
- Do not duplicate component or durable documentation in Vocs pages; import the owning Markdown file.
- Keep app-specific OpenPencil sources under their owning app; keep shared identity sources in `brand/icons/`.
- Do not treat files in `brand/` as Apache-2.0 licensed unless a file explicitly says so.
- Do not add cross-platform abstractions until they remove real duplication or encode a stable boundary.
- Prefer lightweight shells until a phase explicitly requires generated Flutter or Gradle projects.

## Checks

- New files live under the narrowest owning directory.
- Empty directories have `.gitkeep` only when the directory is part of the planned structure.
- Generated outputs are either ignored or placed under the documented generated folder.
- Naming follows the plan: Rust crates `ward-pulse-*`, Dart package prefix `ward_pulse`, Kotlin package `app.wardpulse` or `io.wardpulse`.
