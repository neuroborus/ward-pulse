# Fixture Validation Tools

Automation for fixture and schema checks.

Every file under `schemas/` and `fixtures/` must parse, and every golden fixture in
`fixtures/snapshots/` must match the schema named for it in `FIXTURE_SCHEMAS`. The schemas are
closed (`additionalProperties: false`), so a stray field, a missing required one, or a value of
the wrong shape fails the gate. A new golden fixture must be listed there: the run fails while
any file in `fixtures/snapshots/` has no schema named for it, so an unchecked fixture cannot pass
for a checked one.

A schema must be named `*.schema.json` for the same reason: that is the glob the checker reads,
and one named otherwise would sit unswept.

Provider fixtures (`fixtures/providers/`) are sanitized payloads from other people's APIs and
have no schema of ours to match; they are checked for syntax only.

The checker reads the keyword subset these schemas use (`type`, `$ref`, `properties`,
`additionalProperties`, `required`, `items`, `enum`, `const`, `anyOf`, `allOf`, `minimum`,
`maximum`, `minLength`, `maxLength`, `maxItems`, `pattern`, and `date-time` for `format`). Every
schema is swept for anything outside that set before the fixtures are checked — branches no
fixture walks into included — so a rule cannot be added that the gate reads past.

Run the checks from the repository root:

```sh
just validate-fixtures
```
