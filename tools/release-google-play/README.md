# Published GitHub bundle preparation

`release_google_play.py` implements a stdlib-only, read-only preparation phase for
phone and Wear AABs produced by the `build` and `publish` jobs in
[`release-github.yml`](../../.github/workflows/release-github.yml). Play apply,
Google authentication and a consuming manual workflow remain pending.

## Interface

Run Python 3.10+ on Linux from the trusted original main dispatch checkout, using
the helper from that checkout. The consuming process supplies `GITHUB_REPOSITORY`,
`GITHUB_SHA` (the full original dispatch SHA), `GITHUB_EVENT_NAME=workflow_dispatch`
and `GITHUB_REF=refs/heads/main`. These values are trusted caller context, not
proof that an arbitrary caller is main. The checkout must be clean, its origin
must identify that GitHub repository, and its HEAD and helper bytes must match
the dispatch commit. Git objects for the selected release and its ancestry must
already be available; preparation never fetches, changes HEAD or executes release
source. Older releases may predate this helper and current-main versions may differ.

Supply a token with only `contents:read` through the `GH_TOKEN` process environment,
never command arguments or files. No credentials are provisioned by this tool.

```sh
python3 tools/release-google-play/release_google_play.py \
  --tag v1.2.3 --output /absolute/existing-parent/fresh-preparation
```

The tag must be explicit stable `vMAJOR.MINOR.PATCH`. `prepare` resolves a published
release, rejects ambiguous identities, peels annotated tags and requires the commit
in the original main history. `binary_contract` reads the four historical version
declarations as immutable data and derives all seven filenames and signer pins.
Unsupported declaration forms fail closed. Phone codes must be positive odd with
the next even Wear code; independent legacy and Push codes must also be positive
and at most 2147483647. Push uses its declared default, without running Gradle.

Only the phone/Wear AABs, `SHA256SUMS` and `provenance.json` are downloaded, using
authenticated exact GitHub asset-ID GETs. `GitHub.download` accepts 200 or at most
three 302 redirects to HTTPS `release-assets.githubusercontent.com` or
`objects.githubusercontent.com`; redirected requests carry no authorization.
Each request has a 30-second socket timeout and bounded reads (2 MiB metadata,
1 MiB receipts, 512 MiB binaries). Ambient proxies and automatic redirects are disabled.
Optional API digests are checked when supplied, including unused binary digests
against receipts. Both downloaded AAB hashes must match the seven-binary receipts.

`retain` creates a fresh private directory outside the checkout, rejecting existing
paths and symlink components. It retains the exact two AABs and two receipts plus
`preparation.json`: sanitized repository, dispatch, release, tag-chain, source and
all nine asset identities, sizes, optional digests and downloaded-file hashes.
Historical producer run/attempt IDs are validated and retained in provenance;
they are receipt claims, not the future Play dispatch IDs or an independent
Actions-run attestation. Tokens, signed redirect URLs and raw remote diagnostics
are excluded from retained metadata and CLI output.

Preparation establishes repository receipt/byte consistency, not independent
signature attestation or Play Console readiness. It does not rebuild, re-sign,
parse signatures or Push tokens, download unused APKs, call Play or perform Google
auth. A later apply phase must re-observe release/tag/source/asset identities and
verify retained local bytes before any Play mutation: remote state can change.

## Offline tests

```sh
python3 -m unittest discover -s tools/release-google-play -p 'test_*.py'
```

Tests inject in-memory transport and neutral synthetic releases; they use no
sockets, HTTP services, credentials, sleeps or external test framework. Real
filesystem tests need temporary scratch and clean it deterministically. All focused
Python runtime (including timing) and the full documentation build belong to HOST
acceptance; Native review of this source supplies no runtime pass. HOST must measure
the focused suite under 60 seconds, without a timing assertion in tests.
