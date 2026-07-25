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

- WFF format version 1 stays declarative: ring **values** come from SHORT_TEXT
  complications (slots 101 / 102) backed by the Wear summary’s first two rings.
- The OpenPencil frame shows the intended two-slot ring composition for a future
  format bump that can draw live arcs; v1 ships labels + percent text.
- Ambient keeps a thin time layer and the WardPulse label; complication chrome hides.
- Tap-to-open the Wear app remains on the face group.
