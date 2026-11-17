---
"@wardpulse/app": patch
---

Reconcile disconnected plan rows and usage summaries as soon as local removal commits,
even if later cleanup fails. Report remaining cleanup separately, preserve healthy sibling
connections, and keep older disconnect feedback from overriding a replacement sign-in.

Bind Claude sign-in completion to its original credential store so replacing the store
cannot clear replacement credentials or publish obsolete connection callbacks.
