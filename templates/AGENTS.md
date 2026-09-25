# Working agreement

Instruction, not description. This repo is `CONTEXT.md`; how it is built is
`ARCHITECTURE.md`; what is enforced is `RULES.md`.

## Before anything

1. Run `leo session --report` — it prints `Next:`, the stage you are in.
2. **Name that stage in your first line. Every reply.**
3. Do that stage. Stop there.

Tools block below STALE or missing? Fix that first: `leo agents --ask`, put
the question to them, then `leo agents --auto`. Never decide which tools are
on. Cannot run commands? Say so and stop — never guess the stage.

## The loop

**Cycle one — build it.** Every stage, in order, one task at a time.

    grill     interview them until it is settled; write it into `## Grill`
    plan      leo plan "<name>"           opens P1, then P2, P3, …
    task      leo task T1                 a file and a to-do per task
    subtask   leo task T1 --sub "<name>"  a heading inside T1.md
    build     write the code for that one task
    manifest  leo scan, fill every row, then leo check
    record    leo record "<subject>"      nothing reaches git
    commit    leo commit                  <- theirs, not yours

**Cycle two — read it.** After a commit, in a NEW session. Cannot edit code.

    brief     leo review <sha>            briefed from the commit itself
    findings  fill the table in .leo/reviews/<sha>.md
    close     leo review --close          <- theirs, not yours

Asked for a stage two ahead — code with no plan, a record with no manifest —
name the skipped stage and its command, then wait. Never quietly. A new goal
is a new plan; task ids never restart. Cannot do a task yet? `leo defer T3
"<why>"` steps over it: never mark it done, never delete it.

## Grill before every task

Once per **task**, once per **subtask**, not once per change. A deferred
subtask is not grilled — that is what deferring it means. No cap on questions;
stop when they confirm, never at a count. Zero is not a grill: `leo check`
fails on `leo:ungrilled`.

## Standing orders

- **Never commit.** End a cycle with `leo record`. `leo commit` is theirs.
- **Never install.** If a tool is MISSING, show them `leo install <name>`.
- **Announce every tool**: `leo use <name>` first. Every ON tool must appear.
- **Never invent a task ID** to justify a hunk.
- The session mode is the developer's. Honour it; never change it.

After you record, tell them to start a **fresh session**. `SESSION.md` is
rewritten on every command; read it after a disconnect.

<!-- leo:tools begin fingerprint=none -->
<!-- `leo agents --auto` writes this. Until it runs you know nothing about
     which tools this session allows — so run it, or ask for it. -->
<!-- leo:tools end -->
