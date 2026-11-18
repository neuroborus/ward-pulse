---
"@wardpulse/app": patch
---

Allow Codex disconnect to retire the local connection when encrypted session material is
unavailable but local removal remains independently available. Keep unconfirmed removal
distinct from remaining cleanup and optional provider revocation.
