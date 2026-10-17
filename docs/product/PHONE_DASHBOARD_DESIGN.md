# Phone Dashboard Design

**Status rules locked 2026-08-13** — how the phone Dashboard says that something is wrong, and
at which level it says it.

**Balance rules locked 2026-10-11** — how it renders a quantity a provider reported.

This document locks **rules, not a composition.** The face, Glance and widget baselines each own
a generated review board because their layout is fixed; the Dashboard is a list whose length is
the user's, so a reference picture would rot faster than it could be drawn. What is locked here
is when a mark appears, what each level of the screen may say, and where the numbers come from.

Implementation must follow this document, and for the status marks it does — checked rule by
rule against the code and read on a device on 2026-10-11, recorded under *Implemented* after
the rules.

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

**Implemented 2026-10-11 — the rules are in the code.** Until today this document told its
reader the marks were unbuilt: *one badge widget renders at every level, at one size*. That was
true when the rules were locked on 2026-08-13; the sentence outlived the defect it described.
Each rule, and the guard or function that enforces it:

| Rule | Where it is enforced |
|---|---|
| 1, silent on `Ok` | the allowance card's `if (allowance.status != ProviderStatus.ok)` guard; the family header's `if (section.flagged > 0)`; `_AppBarProblems`, which builds nothing unless `problems.first` matches and otherwise returns `SizedBox.shrink()` |
| 2, what a rollup counts | the `flagged` fold building each section — an account's unhealthy cards, or one for an unhealthy account that produced none — with `worstProviderStatus` taken over accounts and allowances together |
| 3, a rollup differs in form | two widgets, not one: the leaf renders `StatusPill`, a glyph; the family header and the app bar render `Badge` carrying a count |
| 4, family color stays identity | the header's accent `Container` takes `providerFamilyColor`, and the status badge sits beside it in the same row |
| 5, one severity scale | `providerStatusColor` for the glyph, `providerStatusChipColors` for the filled counts, ranked by `providerStatusSeverity`; no call site enumerates statuses |
| 6, the top mark is a way in | the app-bar badge is an `InkResponse` calling `_revealProblem`, which selects the Dashboard tab and then scrolls to `dashboardProblems(…).first`, read off the same order the screen renders with |
| 7, distinct glyphs | `_statusIcon` in `status_pill.dart`, one icon per status |

Four tests in `dashboard_screen_test.dart` hold it: *aggregate spend card shows money and
nothing to measure it* (a card with nothing to mark carries no pill), *shows allowances from
every connected provider* (healthy families render no `Badge` at all), *shows Cursor Models and
Other Models plan pools* (the healthy pool carries no pill, the rate-limited one carries its
own glyph, and the header carries the count `1`), and *a family joining reranks, and the badge
follows the cards* (what the app-bar mark scrolls to follows the rendered order).

One thing a grep will find and misread: `_statusIcon` still maps `ok` to a check. Nothing on
the Dashboard draws it — the card's guard is what keeps it off the screen — and it exists for
the Settings diagnostics rows that Out of scope below exempts.

**Seen on a device, both halves.** Read on the canonical phone AVD
`wardpulse_phone_play_api36` on 2026-10-11. First with a healthy payload: no mark on any
allowance card, no badge in any family header, nothing in the app bar — rule 1's norm half,
which is the half that is easy to get wrong by drawing something.

An hour later a Claude window crossed its own threshold unprompted, and the rest of the rule
set was visible in one frame. The app bar carried an amber badge reading `1` beside the refresh
action. The Claude family header carried an amber `1` beside its orange accent bar, which went
on naming the family — rule 4. Under it, the `5-hour session` card at `13% left` carried an
amber warning **triangle**: rule 3, the leaf stating a fact with a glyph while the two levels
above it carry counts. `Weekly plan` at 67% beside it was bare, as was Codex `Weekly plan` at
92%, so rule 1's exception and its norm were legible against each other at once. The Codex
header carried no badge at all, nothing under it being flagged — rule 2. And the counts agreed
down the nesting: one unhealthy card, `1` on its family header, `1` in the app bar.

Rule 6 needed a gesture, so it got one. From the **Widget** tab, tapping the app-bar badge
switched to the Dashboard and brought the Claude section to the top of the viewport with its
flagged card directly beneath — a way in, not a copy.

Rule 5 showed itself in the colours: the glyph is amber **ink** and both badges are amber
**fills**, which is `providerStatusColor` and `providerStatusChipColors` travelling together as
the rule requires.

One AVD, one build. The tests above stand behind the cases a reader cannot stage on demand —
every status in the glyph vocabulary, every shape of count — rather than behind the rules as a
whole.

## Reporting-key feedback

**Revision 2026-10-17.** A saved reporting key is not proof of reporting access. These
rules apply to **OpenAI · Platform reporting**, **Anthropic · Organization reporting**
and **Cursor · Team Admin API**, independently of each family's plan connection.

- Saving or replacing a key starts one check through the existing live-load lifecycle.
  **Checking…** means that request is running; **Not verified** means reporting access
  for the saved key is not currently confirmed. **Connected** requires a successful
  report for the current credential version. Cached data, mock data and a healthy
  sibling plan row cannot supply that confirmation.
- Dashboard names each failed reporting connection, including when no account data
  loaded or several connections failed. Its safe outcome matches the corresponding
  Providers row: **Key rejected** for authentication rejection, **Access denied** for
  insufficient reporting access, and distinct wording for request, rate-limit,
  saved-key-read and reporting-data failures. An optional user label supplements the
  connection name; it never replaces the family and connection kind.
- **Edit key**, where offered, opens that exact reporting connection's key editor.
  A reporting failure must not direct the user to the sibling plan login. Providers
  keeps status and supporting text below the connection details, readable when text
  wraps, without crowding the existing trailing actions.
- The app owns completion after Save, so leaving Providers does not lose the result.
  Removing or replacing a key retires an obsolete result. Changing only **Label**
  preserves the key and does not start another check; a label-write failure after a
  successful key save is reported separately and does not cancel the key's check.
- These messages preserve the existing glyph vocabulary, severity scale and rollup
  rules. Reporting failures do not create automatic alerts; alerts remain user-configured.

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
