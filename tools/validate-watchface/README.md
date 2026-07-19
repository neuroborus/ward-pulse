# Watch Face Validation

Validates the canonical WFF XML with Google's Watch Face Format validator 1.7.0. The
checksum-pinned JAR is downloaded once from its immutable GitHub release asset and cached
under `${XDG_CACHE_HOME:-$HOME/.cache}/wardpulse/`.

Run from the repository root:

```sh
just validate-watchface
```

The validator also runs as part of `just check-watchface` and watch-face CI.
