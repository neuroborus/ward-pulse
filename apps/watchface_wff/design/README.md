# Watch Face Format ring layouts

**Baseline locked 2026-07-25** — same contract as Wear:
[`docs/product/WATCH_RING_DESIGN.md`](../../../docs/product/WATCH_RING_DESIGN.md).

```sh
node tools/render-watch-ring-designs.mjs
```

Representative copies: `round-3-plan-credits`, `round-3-plan-split`, `round-3-budget-periods`,
`round-3-plan-untouched`, `round-1-plan-credits`, `round-credits-only`, `round-ambient-3`,
`round-ambient-budget`. The generator's `wffFiles` set is the source of truth.
The adaptive revision also mirrors one/two-band pair boards and D/7D/M budget fits in
active/ambient, with unchanged N3 art. Native geometry, transitions and final public captures
remain Pending under the dated baseline; review art is not installed-renderer evidence.
Runtime face: `src/main/res/raw/watchface.xml` (concentric remaining arcs).
