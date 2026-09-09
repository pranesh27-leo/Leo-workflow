# How plans are stored

    .leo/plans/ROADMAP.md          every change, its order and its status
    .leo/plans/C2-build/plan.md    the change plan: goal, non-goals, tasks, budget
    .leo/plans/C2-build/T1.md      one file per task -- its grill, its decisions
    .leo/plan.md                   a pointer to the change in flight

## Why a task plan is a file and a subtask plan is a heading

Every task gets grilled, so every task has a plan. Every subtask gets grilled
too. The naive shape -- one file per subtask -- turns a five-task change into
twenty files, and an agent that must read four of them to answer one question
pays four file reads to do it.

So: **one file per task, subtasks are headings inside it.** A subtask's grill,
decision and to-do sit under `## T1.2 <name>` in `T1.md`. Reading T1.md gives
you the parent's reasoning and every child's in one read, which is the shape
the agent actually needs. Files split only when a task exceeds ~200 lines.

## What goes in a task plan, and what does not

Record the **decisions**, not the transcript. A grill that ran twelve questions
produces maybe five lines here -- the ones where the answer could have gone the
other way. Questions whose answer was the obvious default are not decisions and
do not earn a line.

The test: if you deleted the line, could someone rebuild the same code from
what is left? If yes, the line was transcript. Delete it.

## Committed, not ignored

`.leo/plans/` is tracked. `.leo/plan.md`, `.leo/manifest.md`, `.leo/session`
and `.leo/tasks/` stay ignored -- those are the state of one working tree at
one moment. A plan is the reasoning behind a change, and that belongs to
everyone who later has to ask "why is this line here".
