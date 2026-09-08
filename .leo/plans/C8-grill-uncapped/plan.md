# Plan: take the cap off the grill

Created: 2026-09-09

## Goal
leo's own text caps the grill in four places — "3–10 questions", "a one-line
fix earns one question, not five", "one question is fine". The vendored skill
imposes no such limit: it says ask the whole frontier each round and stop when
the frontier is empty and the developer confirms shared understanding. leo is
overriding the thing it vendored. Remove every number and defer to the skill's
own stop condition.

## Non-goals
- **The vendored skill is not edited.** It is Matt Pocock's file, copied
  unmodified, and the whole reason it is vendored is that its definition
  cannot drift. leo's job is to say *when* to grill, never *how much*.
- No change to the grill gate. `leo check` still fails on `leo:ungrilled`;
  what changes is what leo says the grill should look like, not whether one
  is required.
- Zero questions is still not a grill. Removing the ceiling is not removing
  the floor.

## Wrong-change signal
A new number appears anywhere. If the fix for "3–10 is too few" is "5–20",
nothing was understood: the point is that question count is the wrong
variable, and shared understanding is the right one.

## Tasks

| #  | Task                                                       | Files                        | Est LOC | Status  |
|----|------------------------------------------------------------|------------------------------|---------|---------|
| T1 | tests: no numeric cap survives anywhere in leo's grill text | t/smoke.sh                   | 40      | done    |
| T2 | workflow.md: rounds until the frontier empties              | templates/workflow.md        | 50      | done    |
| T3 | AGENTS.md, task.md, check.sh: drop the scaling advice       | templates/, core/cmd/check.sh | 35     | done    |
| T4 | README, GUIDE, DEMO describe the grill as it now is         | README.md, GUIDE.md, DEMO.md | 45      | done    |

## Budget
est: 170 LOC
