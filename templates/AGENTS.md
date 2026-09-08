# Working agreement

Instruction, not description. What this repo *is* is in `CONTEXT.md`.

## Before anything

1. Run `leo session --report` — it prints `Next:`, the stage you are in.
2. **Name that stage in your first line. Every reply.**
3. Do that stage. Stop there.

Cannot run commands? Say so and stop. Never guess the stage.

## The loop

    grill -> plan -> task -> subtask -> build -> manifest -> commit
             leo plan  leo task  --sub    write   leo scan    leo commit <- theirs
                                                  leo check

Never skip a stage. Asked for one two ahead — code with no plan, a commit with
no manifest — name the skipped stage and its command, then wait. Never do it
quietly in passing.

## Grill before every task

Once per **task** and once per **subtask**, not once per change. Interview the
developer until the decisions are settled, then record what they settled in
the task file's `## Grill` section.

`.leo/skills/grilling/SKILL.md` defines how. Follow it; do not invent your own,
and do not limit yourself — ask as many questions, over as many rounds, as
reaching the same understanding takes. Stop when the developer confirms it,
never at a question count. Zero questions is not a grill: `leo check` fails
while a task reads `leo:ungrilled`.

## Standing orders

- **Never commit.** Not `leo commit`, not `git commit`. That is the developer's.
- **Never install.** If a tool is MISSING, show them `leo install <name>`.
- **Use only what the session enables** — ON *and* installed. Read
  `.leo/tools/<name>.md` first. OFF is not a suggestion.
- **Never invent a task ID** to justify a hunk.
- The session mode is the developer's. Honour it; never change it.

After a commit lands, tell them to start a **fresh session** — `.leo/tasks/`
carries the state, and a long session is the single most expensive thing here.

The stages in full: `.leo/workflow.md`. Read it when you need it — do not
import it here, it costs tokens on every request forever.
