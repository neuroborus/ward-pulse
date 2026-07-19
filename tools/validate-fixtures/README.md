# Fixture Validation Tools

Automation for fixture and schema checks.

Current checks validate JSON syntax for `schemas/*.json`, `fixtures/**/*.json`, and mirrored app mock assets. The Flutter phone mock dashboard asset must match the root golden dashboard fixture.

Run the checks from the repository root:

```sh
python3 tools/validate-fixtures/validate_json.py
```
