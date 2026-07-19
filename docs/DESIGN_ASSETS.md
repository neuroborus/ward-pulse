# Design Assets

WardPulse uses OpenPencil for editable icon sources. Adoption is incremental: existing runtime
assets stay in place until an OpenPencil source replaces them.

![WardPulse app icon](../brand/icons/wardpulse.svg)

## Format And Viewing

OpenPencil stores editable documents as `.fig` files, the same binary document format used by
Figma. The repository build does not require the OpenPencil desktop app.

For a quick visual check, open the tracked SVG or one of the runtime PNG files in a browser or image
viewer. On Linux:

```sh
xdg-open brand/icons/wardpulse.svg
```

The Design Assets page is also available through the local documentation site:

```sh
just docs-dev
```

OpenPencil installation is optional. Use the [web app](https://app.openpencil.dev/) without
installing anything, or install a desktop build from the
[official releases](https://github.com/open-pencil/open-pencil/releases) for offline editing and
file associations. Open `brand/icons/wardpulse.fig` with `Ctrl+O` on Linux and Windows.

## Ownership

- Shared WardPulse identity sources belong in `brand/icons/`.
- App-specific sources belong in a `design/` directory under the owning app.
- Exported runtime assets belong in the consuming platform's normal asset or resource directory.

Runtime targets are `apps/phone_flutter/assets/` or its Android `res/` tree,
`apps/wear_android/app/src/main/res/`, and `apps/watchface_wff/src/main/res/`.

Do not create a repository-wide design system or duplicate a source file between owners. Files
under `brand/` remain outside the Apache-2.0 source license unless explicitly stated otherwise.

## Palette

- Brand primary: `#1F7A5A`.
- Brand sheen: `#155B45` → `#1F7A5A` → `#2A9D78` → `#1F7A5A` → `#155B45`.
- On-brand foreground: `#F4FBF8`.
- Performance accent: `#006B60` (light) / `#67E8D4` (dark).
- Dark surface: `#101412`.
- Success: `#176B3A` (light) / `#65D78A` (dark).
- Warning: `#E6C349`.

Use brand color sparingly on graphite surfaces. Use the performance accent for primary actions and
data visualization; reserve success, warning, and error colors for status meaning. Keep the sheen
symmetric and limited to identity surfaces; do not apply decorative gradients to data or status UI.

## Mark

The pulse communicates activity and throughput. The small eye signals watchful, local monitoring.
Keep the eye in the upper-right of the mark and preserve its scale relative to the pulse.

## Source And Runtime Files

Track each editable `.fig` source and its required runtime exports in Git. Prefer one source file
per independently exported icon so export commands do not depend on unstable node IDs.

The `.fig` file is the source of truth. PNG and SVG exports are generated artifacts: do not edit
them by hand. Commit runtime exports when an application build consumes them, so normal builds do
not require OpenPencil.

The phone adaptive icon uses a native Android `VectorDrawable` derived from the same mark. Keep its
geometry and palette aligned when the editable source changes.

## Setup

The repository pins the OpenPencil CLI as an npm development dependency. Install it with the
existing workspace toolchain:

```sh
npm ci
```

The root tooling provides a small Node compatibility runner and a narrow security override for the
current CLI. Do not install a separate global OpenPencil CLI.

## Export

Regenerate all tracked launcher exports:

```sh
just export-icons
```

Export SVG at scale 1 by default:

```sh
just export-design brand/icons/wardpulse.fig brand/icons/wardpulse.svg
```

Pass the format and scale for raster platform resources:

```sh
just export-design brand/icons/wardpulse.fig path/to/ic_launcher.png png 4
```

Export directly to the owning runtime directory, review the result, and stage the `.fig` source
with every changed export.
