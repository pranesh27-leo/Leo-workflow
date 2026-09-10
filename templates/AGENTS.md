# Working agreement

Instruction, not description. What this repo *is* is in `CONTEXT.md`.

## Before anything

1. Run `leo session --report` — it prints `Next:`, the stage you are in.
2. **Name that stage in your first line. Every reply.**
3. Do that stage. Stop there.

Cannot run commands? Say so and stop. Never guess the stage.

## The loop

    1  grill -> plan -> task -> subtask -> build -> manifest -> record
       leo plan  leo task  --sub   write   leo scan+check  leo record
       repeat 1 per part; nothing is in git until  leo commit <- theirs
    2  brief -> read -> findings -> close        <- after a commit, NEW session
       leo review <sha>              leo review --close <- theirs

Never skip a stage. Asked for one two ahead — code with no plan, a record with
no manifest — name the skipped stage and its command, then wait. Never quietly.

Cycle two reads a commit and **cannot edit it**. Want to change a line? That
is a finding; the fix is a new cycle one.

## Grill before every task

Once per **task**, once per **subtask**, not once per change. Interview the
developer until the decisions are settled; write them into `## Grill`.

`.leo/skills/grilling/SKILL.md` defines how. Follow it; invent nothing.
No cap on questions or rounds — stop when the developer confirms, never at a
count. Zero is not a grill: `leo check` fails on `leo:ungrilled`.

## Standing orders

- **Never commit.** End a cycle with `leo record` — it files the message and
  lands nothing. `leo commit` and `git commit` are the developer's.
- **Never install.** If a tool is MISSING, show them `leo install <name>`.
- **Announce every tool**: `leo use <name>` before using one. It shows the
  developer and logs it. Every ON tool must appear; OFF is refused and recorded.
- **Never invent a task ID** to justify a hunk.
- The session mode is the developer's. Honour it; never change it.

After you record: tell them to start a **fresh session** — a long session is
the most expensive thing here. Cycle two opens once they commit.

The stages in full: `.leo/workflow.md`. Read on demand — never import it
here; that costs tokens on every request forever.
