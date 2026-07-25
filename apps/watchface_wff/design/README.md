# Watch Face Format ring layouts

Editable OpenPencil source: `rings.fig` (source of truth). `round-2-slots.svg` is a
generated review export.

```sh
sed "s/const target = 'wear'/const target = 'wff'/" tools/create-watch-ring-designs.fig.js | \
  node tools/openpencil.mjs eval brand/icons/wardpulse.fig \
  --stdin -w -o apps/watchface_wff/design/rings.fig

node tools/openpencil.mjs export apps/watchface_wff/design/rings.fig \
  --node 0:4 -f svg -o apps/watchface_wff/design/round-2-slots.svg
```

## Layout

- WFF format version 1: slots 101 / 102 prefer `RANGED_VALUE` from the Wear ring
  complications and draw live arcs + percent text; `SHORT_TEXT` remains a fallback.
- Ambient keeps a thin time layer and the WardPulse label; complication chrome hides.
- Tap-to-open the Wear app remains on the face group.
