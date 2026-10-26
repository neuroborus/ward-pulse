# Form input, error and action visibility

Use when judging a composite field or whether validation feedback is revealed. Keep the
owner's actual contract explicit: an editable input, readable error and reachable action
are separate observations. Input visibility alone does not satisfy an error-reveal contract.

A field wrapper can include a label, editor, help and multiline error. Its center can be
outside a clip while the editor remains visible and focused. A failed wrapper hit test
does not establish that the editing target is inaccessible, nor locate the error. A passing
wrapper hit test or retained focus does not establish that every child is visible.

Identify the actual editing target and its hit region separately from the wrapper. Check
its bounds, visible clipping and effective focus/input behavior using the existing case
evidence. Keep successful focus separate from visibility; offscreen inputs can retain focus.
Inspect the validation error's own bounds and complete rendered text independently.

Compare each region with the actual scroll viewport and the area left unobscured by the
keyboard in the observed state, including active clips and insets. A whole-screen rectangle
or the wrapper's bounds is not the usable viewport. Record missing or unavailable geometry as
unknown; do not infer it from a nearby widget or from the failed assertion alone.

After actual validation settles, inspect the input, full error and relevant actions in
that same state. If the contract requires revealing the error, verify the resulting
viewport after the existing reveal/scroll behavior and whether the error is readable and
the relevant action is reachable. A visible focused editor cannot replace that check or
justify weakening a regression assertion that requires the error to be revealed.

Report supported facts separately from hypotheses: identify which target was inspected,
which region is clipped and which observations remain unavailable. Describe a hidden error
as such when proved; do not broaden it to an inaccessible input without input evidence.
Harness geometry and test outcomes remain distinct from native runtime acceptance.
