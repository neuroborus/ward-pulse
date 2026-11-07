---
"@wardpulse/app": patch
---

Keep debug Mock data on the phone widget and watch when background sync runs. Background
work now skips provider reads, publications, recovery, alerts and STALE marks while Mock data
is on or its setting cannot be read, and stops if Mock is turned on mid-run. Release builds
are unaffected.
