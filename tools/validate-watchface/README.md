# Watch Face Validation

Validates the canonical WFF XML with Google's Watch Face Format validator 1.7.0. The
checksum-pinned JAR is downloaded once from GitHub release asset `646791144`, verified
against SHA-256 `fb3262aa146de24c169a1d451901b4df2bfedca28a27c3c168a487e02d393771`, and cached
under `${XDG_CACHE_HOME:-$HOME/.cache}/wardpulse/`.
Upstream assets can be removed or replaced; the explicit asset/checksum pair pins content
without guaranteeing availability.

Run from the repository root:

```sh
just validate-watchface
```

The validator also runs as part of `just check-watchface` and watch-face CI.
