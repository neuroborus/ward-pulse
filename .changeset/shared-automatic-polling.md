---
"@wardpulse/app": patch
---

Share automatic polling admission across foreground and background engines, retain attempt
spacing after failures and restarts, and defer reset wakes until eligible. Preserve cached
timestamps and suppress new alerts or recovery evidence for skipped connections while keeping
explicit refresh and connection checks available under their existing guards.
