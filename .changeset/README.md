# Product changesets

Use standard Changesets Markdown fragments in this directory. Every release fragment must
target only `@wardpulse/app`, the private logical product in
[`tools/release`](../tools/release/README.md#product-ledger). Root tooling and the docs
workspace are not product version owners, even though npm discovers them.

For example, a patch fragment has this front matter followed by a meaningful description:

```md
---
"@wardpulse/app": patch
---

Describe the actual change and its effect on WardPulse users or release operators.
```

Choose `patch`, `minor` or `major` from the actual behavior and requested release scope.
Audit the requested repository-wide range, pending fragments and generated changelog before
adding a fragment. Add only missing coverage; an existing fragment or a successful stock
status does not prove complete coverage. Apps and core live outside the logical workspace,
so stock `--since` package detection can miss their changes.

See the [release owner](../tools/release/README.md) for stock commands, version ownership and
manual publication boundaries. Changesets consumes fragments during a version cut; do not
edit its generated changelog by hand.
