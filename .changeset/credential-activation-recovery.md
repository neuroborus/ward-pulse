---
"@wardpulse/app": patch
---

Keep failed credential activations closed when another connection saves local data, so
restart recovery preserves the prior confirmed credential and explicit reconnect stays usable.
