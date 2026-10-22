# Published GitHub bundles and Play apply

`release_google_play.py` implements stdlib-only preparation and explicit Play apply for
phone and Wear AABs produced by the `build` and `publish` jobs in
[`release-github.yml`](../../.github/workflows/release-github.yml). Preparation is
read-only. Apply targets the fixed `app.wardpulse` application in one Play edit.
Google authentication setup, a consuming manual Play workflow and hosted acceptance
remain pending.

## Preparation interface

Run Python 3.10+ on Linux from the trusted original main dispatch checkout, using
the helper from that checkout. The consuming process supplies `GITHUB_REPOSITORY`,
`GITHUB_SHA` (the full original dispatch SHA), `GITHUB_EVENT_NAME=workflow_dispatch`
and `GITHUB_REF=refs/heads/main`. These values are trusted caller context, not
proof that an arbitrary caller is main. The checkout must be clean, its origin
must identify that GitHub repository, and its HEAD and helper bytes must match
the dispatch commit. Full Git history, including the selected release and its ancestry,
must already be available (no shallow checkout); the helper never fetches, changes HEAD
or executes release source. Older releases may predate this helper and current-main
versions may differ.

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
signature attestation or Play Console readiness. Preparation does not rebuild, re-sign,
parse signatures or Push tokens, download unused APKs, call Play or perform Google auth.

## Apply interface

Use the same trusted original-main dispatch context and full Git history described
above. `verified_preparation` requires the saved repository and dispatch identity
to match that context. Keep `GH_TOKEN` available for fresh read-only GitHub observation.
Supply the externally obtained androidpublisher-scoped access token only through
`PLAY_ACCESS_TOKEN` in the consuming step environment. Never put tokens in arguments,
credential files or retained artifacts. This helper neither generates tokens nor
reads service-account JSON or Android signing secrets.

```sh
python3 tools/release-google-play/release_google_play.py apply \
  --preparation /absolute/existing-parent/fresh-preparation \
  --phone-track qa --wear-track wear:qa --status draft
```

All four apply options are required; the example selects existing tracks and supplies
no defaults. `--status` accepts `draft` or `completed`. Mobile track IDs have no form
factor prefix; Wear IDs start with `wear:`. The application, first manual Console
upload, Play App Signing, Wear form-factor setup and appropriate Play permissions
must already exist. The helper discovers actual tracks and bundles, creates no tracks
and substitutes no destinations.

Before opening an edit, `verified_preparation` reuses the preparation contracts to
revalidate `preparation.json`, both AABs, `SHA256SUMS` and `provenance.json`, including
local sizes/hashes and the newly observed published release, peeled tag/source and
all nine asset identities. It rejects symlinks, missing or unexpected retained files.
This observation provides no atomic exclusion from later external changes.

`apply` checks both selected track states before uploading. A listed bundle is reused
only on an exact versionCode/SHA-256 match; otherwise the retained bytes are uploaded
and the returned code/hash must match. A conflicting code, duplicate listing or code
referenced by a track but absent from the bundle listing requires Console resolution.
An absent listing cannot establish that a historically consumed code is available:
Play may reject the upload. Versions are never bumped, rebuilt or re-signed. Legacy
WFF and the Push APK already embedded in Wear are never separately uploaded.

Saving a draft preserves the completed release and its retained codes. Exact drafts
can be promoted to completed, and matching states are idempotent. A completed request
may replace one older completed code; multiple retained completed codes require a
Console retention decision. Newer versions, conflicting drafts and inProgress/halted
rollouts are rejected. An already completed bundle cannot be saved as a draft. Only
the two selected tracks are updated, preserving unrelated tracks. The single edit is
validated, then committed with `changesInReviewBehavior=ERROR_IF_IN_REVIEW`; there is
no review-cancellation or `changesNotSentForReview` fallback. Commit success proves
neither review completion nor tester availability.

Each Play request has a 60-second socket timeout and a bounded 2 MiB response;
automatic redirects, ambient proxies and automatic retries are disabled. Diagnostics
distinguish preparation-only failure from an attempted Play operation and exclude
tokens, authorization headers and raw response bodies.

## Interrupted or uncertain apply

Before each mutation, `Play.request` exclusively creates and syncs `.play-operation`
inside the retained directory. Only a confirmed response clears it. A failed request,
lost response, mismatched upload/track response or process interruption leaves this
barrier; no subsequent mutation is replayed automatically. A fresh invocation rejects
an existing marker. The marker contains only fixed recovery guidance, no credentials
or remote response data. Retain this directory when investigating a failure.

Inspect actual Play server state in Console before removing the marker manually and
retrying. A new edit and read-only queries may be necessary to inspect state after an
uncertain commit; that inspection does not authorize replay. Reconcile exact bundle
hashes/codes and both track states, including whether the commit took effect. If the
outcome remains ambiguous, leave the marker and resolve it in Console. Removal is an
operator recovery action, not a claim that a missing bundle listing proves upload
availability. Ordinary reruns always discover current bundles/tracks and revalidate
GitHub and retained input; no previous local apply result is trusted.

## Offline tests

```sh
python3 -m unittest discover -s tools/release-google-play -p 'test_*.py'
```

Tests inject in-memory transport and neutral synthetic releases; they use no
sockets, HTTP services, credentials, sleeps or external test framework. Real
filesystem tests need temporary scratch and clean it deterministically. All focused
Python runtime (including timing) remains pending HOST acceptance; Native review of
this source supplies no runtime pass. HOST must measure the focused suite under 60
seconds, without a timing assertion in tests. The unchanged `just check-docs` is a
separate pending HOST acceptance check.
