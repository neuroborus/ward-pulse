# Phone Dashboard Design

**Status rules locked 2026-08-13** — how the phone Dashboard says that something is wrong, and
at which level it says it.

**Balance rules locked 2026-10-11** — how it renders a quantity a provider reported.

This document locks **rules, not a composition.** The face, Glance and widget baselines each own
a generated review board because their layout is fixed; the Dashboard is a list whose length is
the user's, so a reference picture would rot faster than it could be drawn. What is locked here
is when a mark appears, what each level of the screen may say, and where the numbers come from.

Implementation must follow this document. The status marks do not yet: one badge widget renders
at every level, at one size, which is the defect those rules exist to end.

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 16 owns the *order* of the same rows; this
document owns their status marks). Palette and family colors: `docs/DESIGN_ASSETS.md`.

## The three levels

The Dashboard nests three scopes, and each has a different job:

| Level | What it states | Source |
|---|---|---|
| Allowance card | this meter's own state | `allowance.status` |
| Family header | how many things this family reports as unhealthy | its rendered cards and the accounts behind them |
| App bar | how many sections a tap can take the reader to | those sections |

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

## Balances

**Locked 2026-10-11.** A purchased allowance card drew its balance as
`62479.294375 credits` — read off a real payload on 2026-10-11, where the same balance reached
the watch as well. `Quantity.label` trimmed trailing zeros and passed everything else through,
which is no help when the tail is not zeros.

1. **A balance is shown in full, to at most one decimal place.** `62,479.3 credits`,
   `1,000 credits`, `320 credits`, `12.5 credits`, `0 credits`. Everything past the first decimal
   is the provider's own arithmetic, and nobody acts on `.294375`. One decimal is already this
   product's precision for a counted thing: remaining percentages stop there, and so does the
   compact form the glanceable surfaces use.
2. **The Dashboard does not compact, and that is what the screen is for.** The face strip, the
   Wear Glance row and the phone home widget all render this balance as `62.5K`
   (`WATCH_RING_DESIGN.md`; `WEAR_GLANCE_DESIGN.md`, revision 2026-10-11). Compaction is a
   property of a **glance**, not of the number: a 42-unit strip, a row read with the wrist up,
   a widget passed over on the way somewhere else — each buys legibility with precision, and
   each is a peer of the others, so two of them disagreeing would be a contradiction. The
   Dashboard is the screen a person opens to read the figure. `62.5K` is plainly an
   abbreviation of `62,479.3` and nobody holding both reads two balances; what they would not
   accept is the abbreviation being the only place the figure can be had.
3. **A long number is grouped every third digit.** `62,479.3 credits`, and `19,213,690,951
   tokens` on the card below it. The separator goes in the integer part only, and a value that
   is not a number keeps its own text ungrouped.

   **Grouping correction 2026-10-11.** This rule was locked earlier the same day as *no digit
   grouping*, on the argument that a separator is locale-dependent, that the product carries no
   `intl` and no `NumberFormat`, and that a comma here "would be a US convention invented inside
   one widget". The first half is true and still is. **The conclusion was false**, and the
   Dashboard disproved it on the device: a `62479.3 credits` balance was read directly above a
   `19,213,690,951 tokens` count, a thumb's width apart on one screen. `formatCount` in
   `dashboard_models.dart` has been hand-rolling that grouping all along, ten lines from the
   function this rule governs, for four call sites — requests and tokens on a provider row, and
   the two in the usage-history footer. Grouping was never waiting on a product-wide decision;
   it was already the convention, and the balance was the exception. The locale objection cannot
   separate the two either, since it applies with equal force to the count already on the screen.

   What settles it is rule 2: the Dashboard is the screen a person opens to read the figure.
   Grouping is what makes a long figure readable, so leaving the balance ungrouped made the one
   card that exists to be read the hardest number on the screen to read.

   One implementation serves both, for the reason rule 4 gives: `_groupDigits` is shared by
   `formatQuantityValue` and `formatCount`, so a balance and the count beside it cannot drift
   apart. It separates the **text** rather than a parsed number, so a balance longer than a
   double can hold is separated without being reshaped, and it carries the sign through rather
   than counting it — grouping a negative formerly wrote a separator straight after the minus.
4. **The rule lives in the display form, not in the widget.** `Quantity.label` is the one
   display form of a reported quantity and this screen is its only caller, so a second
   formatter beside it would be a second rule waiting to disagree. A value that is not a number
   keeps its own text: inventing a rounding for something unparsed would say more than the
   payload does.
5. **The watch is never handed this form.** `watch_sync_service.dart` puts the provider's own
   `value` and `unit` into the payload, and each watch surface compacts for itself. A balance
   rounded twice would round differently.

## Out of scope

- **Settings diagnostics rows** keep their pill: a row that states one thing's state is not a
  level of this hierarchy.
- **Row order** — `DEVELOPMENT_PLAN.md` Phase 16. Order answers "what comes first", this
  document answers "what speaks at all".
- **Alerts.** User-configured threshold alerts render as their own list; a status mark is
  chrome about a provider, not an entry in that list.
- **Review art.** See the header: rules, not a composition.
