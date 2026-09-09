# Working agreement

Instruction, not description. What this repo *is* is in `CONTEXT.md`.

## Before anything

1. Run `leo session --report` — it prints `Next:`, the stage you are in.
2. **Name that stage in your first line. Every reply.**
3. Do that stage. Stop there.

Cannot run commands? Say so and stop. Never guess the stage.

## The loop

    1  grill -> plan -> task -> subtask -> build -> manifest -> commit
       leo plan  leo task  --sub   write   leo scan+check  leo commit <- theirs
    2  brief -> read -> findings -> close        <- after a commit, NEW session
       leo review <sha>              leo review --close <- theirs

Never skip a stage. Asked for one two ahead — code with no plan, a commit with
no manifest — name the skipped stage and its command, then wait. Never do it
quietly in passing.

Cycle two reads a commit and **cannot edit it**. Want to change a line there?
That is a finding. The fix is a new cycle one.

## Grill before every task

Once per **task** and once per **subtask**, not once per change. Interview the
developer until the decisions are settled, then record what they settled in
the task file's `## Grill` section.

`.leo/skills/grilling/SKILL.md` defines how. Follow it; do not invent your own.
No cap on questions or rounds — stop when the developer confirms, never at a
count. Zero is not a grill: `leo check` fails on `leo:ungrilled`.

## Standing orders

- **Never commit.** Not `leo commit`, not `git commit`. That is the developer's.
- **Never install.** If a tool is MISSING, show them `leo install <name>`.
- **Use only what the session enables** — ON *and* installed. Read
  `.leo/tools/<name>.md` first. OFF is not a suggestion.
- **Never invent a task ID** to justify a hunk.
- The session mode is the developer's. Honour it; never change it.

After a commit lands: tell them to start a **fresh session** — a long session
is the single most expensive thing here — and to open cycle two in it.

The stages in full: `.leo/workflow.md`. Read it when you need it — do not
import it here, it costs tokens on every request forever.
