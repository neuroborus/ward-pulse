---
"@wardpulse/app": patch
---

Keep Claude plan sign-in usable after a failed authorization code. Instead of leaving the
dialog stuck or retrying a spent attempt, it shows the error with Restart sign-in and Cancel.
Restart sign-in begins a fresh authorization, and an existing connection stays in place until
a new sign-in succeeds.
