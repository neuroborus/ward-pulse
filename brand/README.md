# WardPulse Brand Assets

Brand assets are not licensed under Apache-2.0 by default. This directory is
reserved for assets that define the official WardPulse product identity.

## Directories

- `icons/`: shared OpenPencil `.fig` sources and exported app and product identity icons.
  `icons/wardpulse-play-icon-512-transparent.png` is an owner-supplied Google Play listing
  raster, not exported from the `.fig` source.
- `store/`: reserved for store copy and supporting brand artwork. The tracked store covers
  and screenshots are in the [phone](../docs/assets/store-phone/README.md) and
  [Wear OS and watch face](../docs/assets/store-wear/README.md) galleries.
- `watchface/`: watch face visual assets and packaging artwork.

## Usage Rules

- Do not treat asset files in this directory as covered by the repository
  source license unless a specific file says otherwise.
- Do not publish apps, forks, store listings, websites, packages, or watch faces
  using WardPulse branding without explicit permission.
- Keep provider logos out of brand assets unless their usage terms explicitly
  allow bundling them.
- Treat `.fig` files as the source of truth and regenerate runtime exports instead
  of editing them by hand.
- Keep brand and source licensing boundaries aligned with `TRADEMARKS.md`.

The ownership and export workflow is documented in
[`docs/DESIGN_ASSETS.md`](../docs/DESIGN_ASSETS.md).
