# Watch Face Validation

Validates the canonical WFF XML with Google's Watch Face Format validator 1.7.0. The
checksum-pinned JAR is downloaded once from GitHub release asset `800984124`, verified
against SHA-256 `6ef308dbc306a9187b5b1f4997a662eb57e26ac3650cebbf2ab583cd38bb609e`, and cached
under `${XDG_CACHE_HOME:-$HOME/.cache}/wardpulse/`.
Upstream assets can be removed or replaced; the explicit asset/checksum pair pins content
without guaranteeing availability.

Run from the repository root:

```sh
just validate-watchface
```

The validator also runs as part of `just check-watchface` and watch-face CI.
