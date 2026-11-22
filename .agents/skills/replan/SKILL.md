---
name: replan
description: Use the moment the developer wants to change the plan mid-way, at any stage. "change the plan", "drop T4", "add a step", "do it differently", "stop, let's rethink". Stop, show where the work stands, grill the change, change the plan with them, log it, and go on from the right stage.
---

# replan

The developer can change the plan at any time. Your job is to make that
cheap and safe: nothing half-done is lost, nothing changes that they did not
agree to, and the plan still says what is true.

## The steps

1. **Stop.** Finish nothing in progress. Do not start the next task. If a
   file is half-edited, say which one and what state it is in.
2. **Show where the work stands.** One line per task: `done`, `in-progress`
   (and what part), `pending`, `later`. Name any code already written for a
   task that might now go.
3. **Ask what changes.** Use their words. If the change is not clear (which
   task, what instead, why), ask. Never fill the gap with a guess.
4. **Grill the change.** Follow `.agents/skills/grill-me/SKILL.md`, for the
   change only. A changed plan is new decisions: what replaces the dropped
   work, whether the goal's Done when still holds, what the change breaks in
   tasks already done, and any wrapper, helper or abstraction it now seems
   to need. If the change touches code you have not read, read it first
   (`.agents/skills/evidence/SKILL.md`). Stop when the developer confirms.
   Add what was settled to the goal's `## Grill`, under the date.
5. **Show the impact before you edit.** For each change: which tasks are
   added, dropped, reordered or changed, and which written code is now
   unused. **Never delete written code on your own.** List it and let the
   developer decide.
6. **Edit the plan only after their yes.**
   - Dropped task: set it to `later` with the reason, or remove it if they
     say so. Never mark it done.
   - New task: the next unused id. Ids never restart.
   - Changed task: change its Done when first, then its to-do.
   - Too big for this plan: a new `plan-<n>.md` in the same goal.
7. **Log it.** One line in the plan's `## Change log`: the date, what
   changed, and why in the developer's words.
8. **Go back to the right stage.**
   - The goal itself changed: back to `understand`, then a full `grill`.
   - Otherwise the change was grilled in step 4: carry on at the next task.

   Say which stage you go to, and why, in one line.

## What this never does

- Change the plan without grilling the change and getting the developer's yes.
- Delete code, tests or task files on its own.
- Lose a task silently. Every task is done, in progress, pending, later, or
  logged as removed.
