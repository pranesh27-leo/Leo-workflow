# How we work

**This file is the authority on what you must do.** It is instruction, not
explanation — if you want the reasoning, the worked examples and the sample
output, that is the human's guide, and it does not overrule anything here.

Five steps. Do the one you were asked for, and stop there.

**First, check the session.** If `leo session` reports a mode, honour it. In
`debugging`, `learning` and `exploration` the developer has asked for detail:
do not compress output, do not shorten your reasoning, do not summarise
something they may need to read line by line. The mode is theirs — never change
it, and if the work has clearly turned into something else, say so and let them
switch it.

No mode ever relaxes what follows. Plan, task IDs, manifest, rules, tests and
human commit apply in every mode, and nothing you are told to be brief about
includes them.

---

## 1. Plan — "plan this", "frame this", "grill me"

Do not write code. Do not summarise. Do not offer a plan yet. Ask questions.

Each round:

1. Ask 3–10 questions. No cap — ask as many as you genuinely need.
2. Give your recommended default with each, so the user can answer "yes",
   "yes", "no, X" instead of writing an essay.
3. **End your reply there.** Do not plan, do not summarise, do not suggest next
   steps. Wait.
4. When the answers land, ask the next round. Stop only when you can paraphrase
   the user's intent back and they confirm it.

Ask about anything that would change the design: tech choices, what already
exists versus what you would build, constraints, integration points, the data
model, failure modes, and above all what is explicitly **out** of scope. If you
are unsure whether a question matters, ask it.

Three rounds or twenty, both are fine. If you feel the pull to be helpful by
proceeding anyway, resist it: planning on assumptions is not helpful, it is
expensive. And it is self-defeating — in step 3 every hunk must name the task it
serves, and that test has teeth only if the tasks are specific and the non-goals
are real. A vague plan justifies anything, and then nothing you wrote can ever
look unwanted.

**Then, and only then**, run `leo plan "<name>"` and fill in `.leo/plan.md`:

- **Goal** — one sentence.
- **Non-goals** — what this change must not touch.
- **Wrong-change signal** — the one observation that would mean this is the
  wrong change entirely.
- **Tasks** — `T1`, `T2`, … exactly that format, one row each, with the files it
  will touch and a LOC estimate.
- **Budget** — `est: <n> LOC`, the sum of the task estimates.

Get approval before writing code.

## 2. Build — "implement T1"

- Set the task's Status to `in-progress` *before* you start and `done` the
  moment it passes — never batched at the end. A session can end without
  warning, and a status you have not written down is lost.
- Write the test first, from the spec, and watch it fail. Then implement.
- One task at a time. If you find work the plan does not cover, say so and ask.
  Do not fold it in quietly.

## 3. Review — "scan this", "produce the manifest"

```sh
leo scan          # writes .leo/manifest.md, one row per hunk
git diff HEAD     # read this, not your memory of what you wrote
```

Fill in `Task`, `Why` and `If deleted` for every row:

- `Task` — the task ID this hunk serves, or `-` if none.
- `Why` — why *that task* requires this hunk. Not what the code does.
- `If deleted` — what concretely breaks without it.

Then:

- **Never invent a task ID to make a hunk look justified.** An honest `-` is the
  entire value of the exercise. Mapping unrequested work onto a plausible task
  is worse than writing no manifest at all.
- If `If deleted` is "nothing" or "no behaviour change", the hunk is not
  necessary. Say so.
- Formatting churn, import reordering and drive-by renames get their own rows,
  and are almost always `-`.
- Never write the `Tests:` line yourself. `leo check` fills it in from a real
  run.
- For each `-` row, recommend one: **revert** (the default — it is scope creep),
  **promote** (genuinely needed; give the exact task line to add to the plan),
  or **split** (worth doing, in its own commit).
- Name the 2–3 rows most deserving human eyes: widest blast radius, anything
  security-relevant, and any judgement call the user has not seen.

## 4. Land — "check it"

```sh
leo check
```

Fix what it reports. If the budget check fails at over 2×, do not review harder
— re-read the original request. An overshoot that large almost always means the
requirement was misread.

Add anything non-obvious you decided to the manifest, in one line: what you
chose, what you rejected, what you accepted as the cost.

**Do not commit.** `leo commit` is the developer's, and it refuses to run
without a human at a terminal. When the checks pass, run `leo session --report`
— it is the whole state of the change on one screen — then show them the
command and stop:

```
Checks pass. 2 files, +47 lines, every hunk mapped to T1/T2.
Ready when you are:

    leo commit "api: limit each key to 60 req/min"
```

Then say what you would want a reviewer to look at first, and wait. Deciding the
work is done is not your call — you are the least qualified party to make it,
having just written the thing.

## 5. Resume — "where were we"

```sh
leo session            # the mode, if the developer set one
leo plan               # the plan, plus "2 of 5 done | in progress: T3"
git diff HEAD          # the code already written
cat .leo/manifest.md   # the review table, as far as it got
```

Continue at the task marked `in-progress`, or the next `pending` one.

## Writing a rule

Any time you fix a bug that could recur, ask: *can a shell command detect this?*
If yes, and no rule catches it already, add `.leo/rules/<NAME>.md` with a
`## Verify` block that exits non-zero when the mistake is present.

If it cannot be shell-detected ("used the wrong algorithm", "missed this edge
case"), write it into the commit message instead.
