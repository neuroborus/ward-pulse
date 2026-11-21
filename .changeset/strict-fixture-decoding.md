---
"@wardpulse/app": patch
---

Reject invalid JSON constants and timestamps without timezones during shared fixture
validation, so malformed inputs cannot pass the gate before reaching phone or watch readers.
