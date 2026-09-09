# How we work

**This file is the authority on what you must do.** It is instruction, not
explanation — if you want the reasoning, the worked examples and the sample
output, that is the human's guide, and it does not overrule anything here.

Two cycles. Seven stages in the first, four in the second. Do the one you
were asked for, and stop there.

```
CYCLE ONE -- build it
grill  ->  plan  ->  task  ->  subtask  ->  build  ->  manifest  ->  commit
           leo plan  leo task  leo task     write it   leo scan     leo check
                     T1        T1 --sub "x"            leo check    leo commit <- theirs
                                                                        |
CYCLE TWO -- read it, in a NEW session                                  v
brief  ->  read  ->  findings  ->  close
leo review <sha>  the diff vs      leo review --close  <- theirs
                  STANDARDS.md
```

**The two cycles do not overlap.** Cycle one writes code and cannot review it;
cycle two reads a commit that already exists and cannot edit it. If you are in
cycle two and you want to change a line, you have found a finding — write it
down. The fix is a new cycle one, and starting it is the developer's call.

`subtask` is a stage, not a formality. A task that turns out to hold three
decisions needs all three asked; before this existed they were settled by
whatever the agent assumed at the moment it started typing.

**Know where you are, and say so.** Before doing what you were asked, work out
which stage this change is in. `leo session --report` computes it and prints it
as `Next:` — it reads the plan, the task files, the manifest and git, so it is
still right after a disconnect. Name the stage in your first line.

**Name a stage that is being skipped.** If you are asked for something two
stages ahead — code with no plan, a commit with no manifest — say which stage
is being skipped and the command for it, then wait. Do not silently proceed and
do not do the missing stage quietly in passing. The developer may well have a
reason; it is theirs to give, not yours to assume.

**First, check the session.** If `leo session` reports a mode, honour it. In
`debugging`, `learning` and `exploration` the developer has asked for detail:
do not compress output, do not shorten your reasoning, do not summarise
something they may need to read line by line. The mode is theirs — never change
it, and if the work has clearly turned into something else, say so and let them
switch it.

**Use only what the session enables.** `leo session` lists every capability as
ON or OFF, and as installed or MISSING. A tool is yours to use only when it is
**ON and installed** — both. For each one that is, read `.leo/tools/<name>.md`
before you use it and follow what it says; those files carry the prerequisites
and failure modes that cost somebody a session to find, and two of them carry a
standing order rather than advice. A capability that is OFF is not a
suggestion: do not use it, do not work around it, and do not turn it on. The
mode is the developer's.

**Never install anything.** If `leo session` reports a tool as MISSING, say so
and show the developer `leo install <name>`. Do not run it, do not run the
underlying installer yourself, and do not work around a missing tool by
installing something else. What goes on their machine is their decision, the
same as committing is.

No mode ever relaxes what follows. Plan, task IDs, manifest, rules, tests and
human commit apply in every mode, and nothing you are told to be brief about
includes them.

---

## 1. Plan — "plan this", "frame this", "grill me"

Do not write code. Do not summarise. Do not offer a plan yet. Ask questions.

**How to grill is `.leo/skills/grilling/SKILL.md`.** Read it and follow it.
It is vendored unmodified and it is the only definition of a grill here —
leo says *when* to grill and never how much.

**There is no limit.** Not on questions, not on rounds. The purpose is to
reach the same understanding the developer already has in their head, and
that is done when it is done. Ask everything that would change the design:
tech choices, what already exists versus what you would build, constraints,
integration points, the data model, failure modes, and above all what is
explicitly **out** of scope. If you are unsure whether a question matters,
ask it — an unnecessary question costs a line, an unasked one costs a change.

**Stop on shared understanding, never on a count.** The skill's condition is
the frontier emptying — every branch of the design tree visited, nothing left
silently assumed — and then the developer confirming. Two rounds or twenty,
whichever that takes. A grill that ends because it felt like enough questions
has not ended, it has been abandoned.

**End every round at the questions.** Do not plan, do not summarise, do not
suggest next steps, do not start work "while you wait". Wait.

If you feel the pull to be helpful by proceeding anyway, resist it: planning
on assumptions is not helpful, it is expensive. And it is self-defeating — at
the manifest stage every hunk must name the task it serves, and that test has
teeth only if the tasks are specific and the non-goals are real. A vague plan
justifies anything, and then nothing you wrote can ever look unwanted.

**Then, and only then**, run `leo plan "<name>"` and fill in `.leo/plan.md`:

- **Goal** — one sentence.
- **Non-goals** — what this change must not touch.
- **Wrong-change signal** — the one observation that would mean this is the
  wrong change entirely.
- **Tasks** — `T1`, `T2`, … exactly that format, one row each, with the files it
  will touch and a LOC estimate.
- **Budget** — `est: <n> LOC`, the sum of the task estimates.

Get approval before writing code.

## 2. Tasks — "make the tasks", "start T1"

Every row of the plan's table gets its own file:

```sh
leo task T1       # creates .leo/tasks/T1.md, or shows it if it exists
leo task          # every task, its to-do and its plan status
```

Fill in **Done when** first — an observable condition, something you can run —
because the to-do falls out of it. Then write the to-do: the steps you will
actually take, small enough that ticking one is honest.

Tick boxes as you go, not at the end. The plan's `Status` column says whether
the task is done; the task file says what is left inside it. Never put a status
in the task file — two copies drift, and the one you did not update is the one
somebody reads.

**Grill before you build it — every task, and every subtask.** Not once per
change. Before the first line of code for `T1`, interview the developer until
the decisions inside `T1` are settled, then record what was settled in the
task file's `## Grill` section and delete the `leo:ungrilled` marker.

How to grill is `.leo/skills/grilling/SKILL.md` — read it and follow it. It is
vendored unmodified and it is the only definition of a grill in this
repository; do not restate it here and do not invent your own.

Record decisions, not the transcript. A question whose answer was the obvious
default settled nothing. Scale the grill to the work: a one-line fix earns one
question, five is theatre, and zero is never allowed.

Break a task up when the grill shows it holds more than one decision:

```sh
leo task T1 --sub "in-memory store"   # a heading inside T1.md, not a new file
```

Each subtask arrives with its own ungrilled marker, and is grilled before it
is built, exactly as its parent was.

An unticked box still fails nothing — the to-do is your working memory, so a
session ending mid-task costs nothing. The **grill** is the one thing here
that blocks: `leo check` fails while the task in flight is ungrilled.

### End the session when the task ends

When a commit lands, say so and stop: **start a fresh session for the next
task.**

An agent session re-reads its entire context on every turn, so the cost of a
session grows with the *square* of its length — the tenth turn is paid for by
the ninety turns after it. Measured on real sessions: cutting a 357-turn
session in half would have cost 33% of its tokens, not 50%. On the same growth
rate, six short sessions cost roughly a seventh of one long one doing the same
work.

This is what `.leo/tasks/` is actually for. The task file was introduced so a
session ending mid-change cost nothing; that same property makes ending a
session *on purpose* the cheapest thing available. A new session reads the
plan, the task file and the manifest — a few hundred lines — instead of
inheriting every tool result from the last four hours.

Nothing enforces this. leo cannot see how long your session has been running
without reading one specific agent's transcript format, and it will not do
that. It is your call, made at the one moment leo can observe.

## 3. Build — "implement T1"

- Set the task's Status to `in-progress` *before* you start and `done` the
  moment it passes — never batched at the end. A session can end without
  warning, and a status you have not written down is lost.
- **If `leo session` reports TDD as ON**, work test-first: write the test from
  the task's "Done when", run it, watch it **fail**, and confirm it failed for
  the reason you expect — a test that passes before you write anything is
  testing nothing. Then the smallest implementation that passes it. `leo task`
  seeds the to-do with those steps while TDD is on.
- If TDD is OFF the developer has chosen their own order. Tests are still not
  optional: `leo check` runs `TEST_CMD` and records the result either way, and
  no mode can switch that off.
- One task at a time. If you find work the plan does not cover, say so and ask.
  Do not fold it in quietly.

## 4. Manifest — "scan this", "produce the manifest"

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

## 5. Land — "check it"

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

When the commit lands, leo asks for the review. **Do not start it here.** End
the session, and open cycle two in a new one — stage 6.

## 6. Review — "review it", "start the review", after a commit lands

A separate cycle, in a **new session**, with `leo session --mode review`. It
begins after `leo commit` prints the ask, and it never runs in the session that
wrote the code — an agent that has just spent an hour building something is the
worst available reader of it, and everything it would carry over is the part
that made it sure.

```sh
leo review              # the last commit, or: leo review <sha>, leo review a..b
```

That writes `.leo/reviews/<sha>.md`. It is briefed, not blank: leo assembles
what cycle one recorded — the goal, the whole manifest, the non-goals, the
wrong-change signal, and the decisions the grill settled — because a review
that does not know what was asked for can only check the code against itself,
and that is how a change that is internally consistent and completely wrong
passes.

**Read in this order, and do not skip the first.**

1. **What was asked for**, in the review file. If it is thin, the dev cycle was
   thin, and that is your first finding.
2. **`.leo/review/STANDARDS.md`** — the rubric, and the only thing a finding
   here has to clear. It is the repository's, not leo's: read the copy in this
   repo, because a team amends it.
3. **The diff** — `git show <sha>` — against both.

The **Signals** section is a grep, not an opinion. It says where to look and
never what to think; most signals are nothing, and clearing one costs a glance.
A signal it did not raise is the failure mode, so never treat the list as the
scope of the review.

Then fill the findings table. One row per finding, severity `blocker` /
`improvement` / `nit`, status `open` / `fixed` / `waived`. The vocabulary is
fixed because `leo review --close` reads it.

- **Every finding names the failure it causes.** If you cannot say what breaks
  or which principle it violates, it is a nit or it is nothing. "I would have
  written it differently" is not a finding.
- **Do not re-litigate scope.** The manifest already answered whether each hunk
  was asked for, and it is quoted in the file. A review that rediscovers scope
  creep is reading the wrong column.
- **Do not inflate, and do not deflate.** A reviewer who files improvements as
  blockers gets ignored on the one that mattered; a reviewer who files a real
  security defect as a nit to avoid an argument has wasted the whole exercise.
- **Zero findings is a claim.** If you found nothing, the verdict has to say
  what you actually read to conclude that.
- **Anything a linter could catch is not a finding.** It is a missing tool, and
  it belongs in `.leo/rules/` — see "Writing a rule" below.

Write the verdict — `ship` or `fix-first`, and one line of why — and name the
2-3 places a human should look first under **Read first**.

Then stop:

```sh
leo review --close
```

It refuses on an unreadable severity or status, on any blocker still `open`,
and on the verdict the template shipped with. **You do not fix the blockers.**
A fix is a new cycle one — `leo plan "fix: <sha> review"` — and waiving one is
the developer's, never yours. Say which you would recommend, and wait.

## 7. Resume — "where were we"

```sh
leo session --report   # the whole change on one screen, including Next:
leo plan               # the plan, plus "2 of 5 done | in progress: T3"
leo task               # every task and how far its to-do got
git diff HEAD          # the code already written
cat .leo/manifest.md   # the scope table, as far as it got
leo review --list      # cycle two: every review, and which are still open
```

Continue at the task marked `in-progress`, or the next `pending` one, at the
first unticked box in its to-do.

An open review is its own thread of work, and it does not block cycle one. Say
it is open, name what it is waiting on — findings, a verdict, or a fix cycle —
and let the developer choose which to pick up.

## Writing a rule

Any time you fix a bug that could recur, ask: *can a shell command detect this?*
If yes, and no rule catches it already, add `.leo/rules/<NAME>.md` with a
`## Verify` block that exits non-zero when the mistake is present.

If it cannot be shell-detected ("used the wrong algorithm", "missed this edge
case"), write it into the commit message instead.
