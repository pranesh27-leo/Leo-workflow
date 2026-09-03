# How we work

Four steps. Do the one the user asked for, and stop there.

---

## 1. Plan  — "plan this", "frame this", "grill me"

Do not write code. Do not summarise. Do not offer a plan yet. Ask questions.

You are the architect, and you do not share the user's head yet. Everything you
assume instead of asking becomes a line of code nobody can defend later.

**The loop.** Each round:

1. Ask 3–10 questions. No cap — ask as many as you genuinely need.
2. Give your recommended default with each one, so the user can answer "yes",
   "yes", "no, X" instead of writing an essay.
3. **End your reply there.** Do not plan, do not summarise, do not suggest next
   steps. Wait.
4. When the answers land, ask the next round. Stop only when you can paraphrase
   the user's intent back and they confirm it.

Ask about anything that would change the design: tech choices, what already
exists versus what you would build, constraints, integration points, the data
model, failure modes, and — above all — what is explicitly **out** of scope.
If you are unsure whether a question matters, ask it.

This may take three rounds or twenty. That is fine. If you feel the pull to be
helpful by proceeding anyway, resist it: planning on assumptions is not helpful,
it is expensive.

**Then, and only then**, run `leo plan "<name>"` and fill in `.leo/plan.md`:

- **Goal** — one sentence.
- **Non-goals** — what this change must not touch.
- **Wrong-change signal** — the one observation that would mean this is the
  wrong change entirely.
- **Tasks** — `T1`, `T2`, … exactly that format, one row each, with the files
  it will touch and a LOC estimate. `leo check` matches on `T<digit>`, and it
  rejects any task ID in the manifest that is not in this table.
- **Budget** — `est: <n> LOC`, the sum of the task estimates.

Get approval before writing code.

**Why this step decides whether step 3 works.** In step 3 every hunk must name
the task it serves. That test has teeth only if the tasks are specific and the
non-goals are real. A vague plan ("improve error handling") justifies anything,
and nothing looks unwanted. A sharp plan makes the extra helper function you
added out of habit stand out as exactly what it is. The grilling is not
politeness — it is what makes unwanted code detectable an hour from now.

## 2. Build  — "implement T1"

- Set the task's Status to `in-progress` in the plan *before* you start, and to
  `done` the moment it passes — not at the end of the session. The session can
  end without warning; a status you have not written down yet is lost, and the
  next session will either redo the task or skip it.
- Write the test first, from the spec, and watch it fail. Then implement.
- One task at a time. If you find work the plan does not cover, say so and ask —
  do not fold it in quietly.

## 3. Review  — "scan this", "produce the manifest"

```sh
leo scan          # writes .leo/manifest.md, one row per hunk
git diff HEAD     # read this, not your memory of what you wrote
```

Fill in three columns for every row:

| Column | What goes in it |
|---|---|
| `Task` | the task ID this hunk serves, or `-` if none |
| `Why` | why *that task* requires this hunk — not what the code does |
| `If deleted` | what concretely breaks without it |

The rules that make this worth anything:

- **Never invent a task ID to make a hunk look justified.** An honest `-` is the
  entire value of the exercise. Mapping unrequested work onto a plausible task
  is worse than writing no manifest at all.
- If `If deleted` is "nothing" or "no behaviour change", the hunk is not
  necessary. Say so.
- Formatting churn, import reordering and drive-by renames get their own rows,
  and are almost always `-`.
- Do not write the `Tests:` line yourself. `leo check` runs the suite and
  records what actually happened, so the commit can never carry a test result
  nobody observed.

Then, for each `-` row, recommend one of: **revert** (the default — it is scope
creep), **promote** (it was genuinely needed; give the exact task line to add to
the plan), or **split** (worth doing, in its own commit).

Finally, name the 2–3 rows most deserving human eyes: the widest blast radius,
anything security-relevant, and any place you made a judgement call the user has
not seen.

## 4. Land  — "check it"

```sh
leo check
```

Fix what it reports. If the budget check fails at over 2x, do not review harder
— re-read the original request. An overshoot that large almost always means the
requirement was misread.

Before handing over, add anything non-obvious you decided to the manifest, in
one line: what you chose, what you rejected, and what you accepted as the cost.
That sentence in the commit message is what someone debugging this in a year
needs.

**Do not commit.** `leo commit` is the developer's, and it refuses to run
without a human at a terminal. When the checks pass, show them the command and
stop:

```
Checks pass. 2 files, +47 lines, every hunk mapped to T1/T2.
Ready when you are:

    leo commit "api: limit each key to 60 req/min"
```

Then say what you would want a reviewer to look at first, and wait. Deciding the
work is done is not your call — you are the least qualified party to make it,
having just written the thing.

## 5. Resume  — "where were we", after a disconnect

Nothing about this workflow lives in the conversation, so a dropped session, a
closed laptop or a week away costs nothing:

```sh
leo plan          # the plan, plus: "2 of 5 done | in progress: T3"
git diff HEAD     # the code you had already written, still there
cat .leo/manifest.md   # the review table, as far as it got
```

Read those three, then continue at the task marked `in-progress`, or the next
`pending` one. This only works if step 2 was honest about the Status column —
that column is the entire memory of a long change.

## Writing a rule

Any time you fix a bug that could recur, ask: *can a shell command detect this?*
If yes, and no rule catches it already, add `.leo/rules/<NAME>.md`. It runs on
every `leo check` from then on, costs no tokens, and outlives the conversation
that learned it.

If it cannot be shell-detected ("used the wrong algorithm", "missed this edge
case"), write it into the commit message instead.
