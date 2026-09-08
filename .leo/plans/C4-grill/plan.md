# Plan: grill every task, and an AGENTS.md that weak models cannot skip

Created: 2026-09-08

## Goal
Two problems, one change. Grilling happens once per change today, so a task
that turns out to hold three unasked decisions gets none of them asked. And
weak models read AGENTS.md and miss the workflow entirely, which makes every
guarantee downstream optional. Vendor Matt Pocock's grill-me skill as the one
definition of a grill, require a recorded grill per task and per subtask, and
rewrite AGENTS.md so it binds instead of suggests.

## Non-goals
- No new grill wording. The skill is vendored as written and attributed; leo
  does not get its own dialect of a thing that already exists.
- No bypass flag. The grill scales to the work -- one question for a typo --
  but there is no `--skip-grill`, because a flag that exists gets used.
- No repo knowledge in AGENTS.md. That moves to CONTEXT.md, which is what
  makes AGENTS.md short enough for a weak model to read to the end.
- CLAUDE.md stays a one-line bridge.

## Wrong-change signal
AGENTS.md grows past ~50 lines. It loads on every request of every session; a
file that costs tokens forever to state something the workflow already states
is a tax, and a long file is exactly what weak models skim.

## Tasks

| #  | Task                                                        | Files                          | Est LOC | Status  |
|----|-------------------------------------------------------------|--------------------------------|---------|---------|
| T1 | vendor grill-me + grilling skills, attributed                | templates/skills/              | 80      | done    |
| T2 | workflow.md: seven stages, grill per task and subtask        | templates/workflow.md          | 70      | done    |
| T3 | `leo task` writes a Grill section; subtasks are headings     | core/cmd/task.sh, templates/task.md | 90 | done    |
| T4 | AGENTS.md rewritten to bind; CONTEXT.md template added       | templates/AGENTS.md, templates/CONTEXT.md | 75 | done    |
| T5 | `leo check` fails on an in-progress task with an empty grill | core/cmd/check.sh              | 45      | done    |
| T6 | rule + smoke for the whole thing                             | .leo/rules/, t/smoke.sh        | 70      | done    |

## Budget
est: 500 LOC
