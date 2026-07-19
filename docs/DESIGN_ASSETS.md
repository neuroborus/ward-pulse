# Design Assets

WardPulse uses OpenPencil for editable icon sources. Adoption is incremental: existing runtime
assets stay in place until an OpenPencil source replaces them.

## Ownership

- Shared WardPulse identity sources belong in `brand/icons/`.
- App-specific sources belong in a `design/` directory under the owning app.
- Exported runtime assets belong in the consuming platform's normal asset or resource directory.

Runtime targets are `apps/phone_flutter/assets/` or its Android `res/` tree,
`apps/wear_android/app/src/main/res/`, and `apps/watchface_wff/src/main/res/`.

Do not create a repository-wide design system or duplicate a source file between owners. Files
under `brand/` remain outside the Apache-2.0 source license unless explicitly stated otherwise.

## Source And Runtime Files

Track each editable `.fig` source and its required runtime exports in Git. Prefer one source file
per independently exported icon so export commands do not depend on unstable node IDs.

The `.fig` file is the source of truth. PNG and SVG exports are generated artifacts: do not edit
them by hand. Commit runtime exports when an application build consumes them, so normal builds do
not require OpenPencil.

## Setup

The repository pins the OpenPencil CLI as an npm development dependency. Install it with the
existing workspace toolchain:

```sh
npm ci
```

The root tooling provides a small Node compatibility runner and a narrow security override for the
current CLI. Do not install a separate global OpenPencil CLI.

## Export

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
