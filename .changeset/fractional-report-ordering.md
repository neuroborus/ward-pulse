---
"@wardpulse/app": patch
---

Preserve fractional UTC report times so a late older refresh cannot replace newer data from
the same second, including in cached data recovered after restart.
