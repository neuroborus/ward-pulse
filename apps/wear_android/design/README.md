# Wear OS design review art

## Watch face rings (locked)

**Baseline locked 2026-07-25** — see
[`docs/product/WATCH_RING_DESIGN.md`](../../../docs/product/WATCH_RING_DESIGN.md).

Primary preview: `preview-3-plan-credits.png`.

```sh
node tools/render-watch-ring-designs.mjs
xdg-open apps/wear_android/design/preview-3-plan-credits.png
```

Variants: `round-3-plan-credits`, `round-3-plan-split`, `round-3-plan-two-pairs`,
`round-3-plan-untouched`, `round-3-plan-near-exhausted`, `round-3-plan-budget`,
`round-3-budget-periods`, `round-3-plan-cell-cleared`, `round-2-plan-credits`,
`round-1-plan`, `round-1-plan-credits`, `round-credits-only`, `round-ambient-3`,
`round-ambient-budget`. Each has a `preview-*.png` beside it, written by the same run; what
each one is for is in the Review variants table of the baseline.

## App Glance legend (locked)

**Baseline locked 2026-07-26** — accepted; see
[`docs/product/WEAR_GLANCE_DESIGN.md`](../../../docs/product/WEAR_GLANCE_DESIGN.md).

Text legend for face ring colors; not a face clone. Refresh pulse (`OK` / `!OK`) is
independent of enabled/disabled (cadence cooldown stays `OK` + gray). Primary preview:
`preview-glance-legend-3.png`.

```sh
node tools/render-wear-glance-designs.mjs
xdg-open apps/wear_android/design/preview-glance-legend-3.png
```

Variants: `glance-legend-3`, `glance-legend-1`, `glance-legend-pair`,
`glance-legend-full`, `glance-legend-budget`, `glance-legend-stale`,
`glance-legend-cadence`, `glance-legend-rate-limit`, `glance-legend-empty`,
`glance-legend-exhausted`.
