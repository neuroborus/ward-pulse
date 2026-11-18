---
"@wardpulse/app": patch
---

Keep accepted provider data and widget rows when older work finishes after a connection
becomes active. Completed missing-credential reads now retain private ownership evidence,
so obsolete partial reports and failures cannot replace newer combined data or mark it stale,
while healthy sibling connections keep their cached reports.
