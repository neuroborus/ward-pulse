# Phone Dashboard Design

**Status rules locked 2026-08-13** — how the phone Dashboard says that something is wrong, and
at which level it says it.

This document locks **rules, not a composition.** The face, Glance and widget baselines each own
a generated review board because their layout is fixed; the Dashboard is a list whose length is
the user's, so a reference picture would rot faster than it could be drawn. What is locked here
is when a mark appears, what each level of the screen may say, and where the numbers come from.

Implementation must follow this document. It does not yet: one badge widget renders at every
level, at one size, which is the defect these rules exist to end.

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 16 owns the *order* of the same rows; this
document owns their status marks). Palette and family colors: `docs/DESIGN_ASSETS.md`.

## The three levels

The Dashboard nests three scopes, and each has a different job:

| Level | What it states | Source |
|---|---|---|
| Allowance card | this meter's own state | `allowance.status` |
| Family header | how many things this family reports as unhealthy | its rendered cards and the accounts behind them |
| App bar | the worst of the sections on screen | those sections |

## Rules

1. **A mark is an exception, never the norm.** `Ok` draws nothing, at any level. A column of
   healthy checkmarks says "nothing happened" once per row and drowns the one triangle the
   screen was opened for — and a filled check outweighs an outlined warning, so the norm ends up
   louder than the problem.
2. **A rollup covers what the level below renders, and nothing the user cannot reach.** A count
   that includes something absent from the screen promises a problem nothing there can explain.
   Cards alone are not the whole of a section, though: an account can read healthy while one of
   its cards crossed its own threshold, and a platform connection reports spend rather than
   meters, so its trouble has no card to appear on. Hence the family header counts **one per
   unhealthy card, or one for an unhealthy account that produced no unhealthy card**, and takes
   its color from the worst of both. The app bar summarizes sections the same way.
3. **A rollup differs from a leaf in form, not in repetition.** The same glyph at the same size
   on three nested levels erases the nesting. The leaf carries the glyph, because it states a
   fact; a rollup carries a **count**, because it states how many facts are below.
4. **Family color stays identity.** The accent bar in a section header names the provider family
   and keeps doing only that, exactly as on the watch, where color is family and status only
   modulates. Status rides beside it, never over it.
5. **One severity scale.** Rank comes from `ProviderStatus::severity` in the core and its Dart
   mirror in `provider_status_severity.dart`. Color follows the shape it paints:
   `providerStatusColor` is ink for a glyph, `providerStatusChipColors` is the container pair a
   filled count sits in, and the two travel together so a fill and its label cannot drift. Do not
   enumerate "the bad statuses" anywhere — that habit once left the product with five scales
   that disagreed.
6. **The top mark is a way in, not a copy.** A rollup earns its place only when the problem is
   off screen, so the app-bar mark navigates: it opens the Dashboard if another tab is showing,
   then brings the first unhealthy section into view. A mark that only repeats what is already
   visible is noise.
7. **Glyphs stay distinct per status** — rate limit, key, clock, warning, error. The vocabulary
   is not the problem and does not need replacing; repeating one entry of it down the screen is.

## Out of scope

- **Settings diagnostics rows** keep their pill: a row that states one thing's state is not a
  level of this hierarchy.
- **Row order** — `DEVELOPMENT_PLAN.md` Phase 16. Order answers "what comes first", this
  document answers "what speaks at all".
- **Alerts.** User-configured threshold alerts render as their own list; a status mark is
  chrome about a provider, not an entry in that list.
- **Review art.** See the header: rules, not a composition.
