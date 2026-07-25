# Wear OS ring layouts

Editable OpenPencil source: `rings.fig` (source of truth). SVG files next to it are
generated review exports — regenerate instead of editing by hand.

```sh
# Rebuild the .fig from the checked-in generator (optional)
node tools/openpencil.mjs eval brand/icons/wardpulse.fig \
  --stdin -w -o apps/wear_android/design/rings.fig < tools/create-watch-ring-designs.fig.js

# Export a frame for review (node ids from `openpencil find`)
node tools/openpencil.mjs export apps/wear_android/design/rings.fig \
  --node 0:32 -f svg -o apps/wear_android/design/round-3-rings.svg
```

## Layout

- Concentric percent rings, selection order outer → inner (max 4).
- Status colors: success / warning / error from the Wear theme tokens.
- Ambient: thinner muted tracks, time + WardPulse label, no filler rings.
- Round (450) and square (390) share the same slot order.
- Runtime Compose rendering lives in `UsageRings` and reads schema v4 `rings`.
