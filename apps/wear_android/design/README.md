# Wear OS ring layouts

OpenPencil sources for WardPulse Wear home rings live here. Editable `.fig` files are the
source of truth; export runtime assets into `app/src/main/res/` when needed.

## Layout brief (Phase 13)

- Show 1–4 simultaneous percent rings; never invent an `Unknown` filler ring.
- Each ring binds one metric: budget today/week/month or a plan/purchased allowance percent.
- Color rings by status (ok / warning / rate-limited / error), using the Wear theme tokens.
- Ambient: keep thin ring arcs and a short label readable without fill decoration.
- Round and square canvases share the same slot order (phone Settings selection order).

OpenPencil art for the 1–4 ring compositions lands in this directory before polish of custom
drawables; Compose currently renders rings from the schema v4 payload.
