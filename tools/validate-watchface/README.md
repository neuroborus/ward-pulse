# Watch Face Validation

Validates the canonical WFF XML with Google's Watch Face Format validator 1.7.0. The
checksum-pinned JAR is downloaded once from GitHub release asset `550531146`, verified
against SHA-256 `28b244289ab748bb2b07017e9f3c06bb76bdf165d6fa55652a5dc64b852c3121`, and cached
under `${XDG_CACHE_HOME:-$HOME/.cache}/wardpulse/`.
Upstream assets can be removed or replaced; the explicit asset/checksum pair pins content
without guaranteeing availability.

Run from the repository root:

```sh
just validate-watchface
```

The validator also runs as part of `just check-watchface` and watch-face CI.
