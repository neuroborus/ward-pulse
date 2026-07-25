# Watch Face Format ring layouts

OpenPencil sources for WardPulse watch-face ring compositions live here. Editable `.fig`
files are the source of truth; do not hand-edit generated runtime resources under
`src/main/res/`.

## Layout brief (Phase 13)

- WFF stays declarative: ring values arrive through complications backed by the Wear summary.
- Slot 0 / slot 1 short-text complications prefer the first two selected rings from schema v4.
- Ambient mode keeps a thin time layer plus the WardPulse label; ring complications hide in
  ambient as today.
- Tap-to-open the Wear app is preserved on the face group.

OpenPencil art for round/square 1–4 ring faces is authored here before replacing the static
RING 1 / RING 2 labels with ring-arc assets.
