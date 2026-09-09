# How to get a number you can defend

The session benchmark reads what real sessions cost. It cannot tell you what
leo saved until there is something to compare against, and two sessions that
did different work are not a comparison — they are two numbers.

## The experiment

Pick **one task you have not done yet**, specific enough that two sessions
would produce roughly the same code. A bug with a known reproduction is ideal.
A feature described in one sentence is not: the two runs will build different
things and the comparison is meaningless.

1. **Run A — without leo.** Fresh session, in a clean worktree. Do not run any
   leo command. Work the task the way you would have before any of this
   existed. Stop when the task is done.
2. **Run B — with leo.** Fresh session, another clean worktree, same starting
   commit, same task, same wording of the request. Grill, plan, task, build,
   manifest.
3. `bash t/bench-session.sh` — the two rows are the result.

Worktrees rather than branches, so neither run can see the other's files:

```sh
git worktree add ../leo-run-a <base-sha>
git worktree add ../leo-run-b <base-sha>
```

## What to compare

**Tokens per turn**, not tokens per session. A leo session has more turns by
design — the grill is turns, the plan is turns — and a raw total would say leo
is expensive without saying whether each turn got cheaper.

Then look at the two components separately, because they have different
prices:

- **fresh** (input + cache writes + output) — full price.
- **cache read** — roughly a tenth of input price, and 95% of the volume.

leo can plausibly move these in opposite directions. It adds fresh tokens
(AGENTS.md on every request, the plan, the task file, the grill) while making
the context more stable and therefore more cacheable. A ratio that collapses
both into one number will hide that, and hiding it is how you end up with a
number that is true and useless.

## What would make the result honest

- **Say which model.** Claude Opus 4.7 and later use a different tokenizer —
  roughly 30% more tokens for the same text. A count is meaningless without it.
- **Run it more than once.** Two sessions is an anecdote. Same task, two runs
  each way, is the minimum worth publishing.
- **Report a loss if you get one.** leo may cost more tokens and be worth it
  anyway: reviewability is the product, cheapness was never the pitch. A
  benchmark that can only confirm is not a benchmark.
- **Do not tune the task until leo wins.** If the first honest task shows a
  loss, that is the result. Pick tasks before you know the answer.

## What this cannot tell you

Whether the code was any good. Tokens are the cheap thing to measure, which is
exactly why it is tempting to let them stand in for value. Two sessions can
cost the same and leave you with a diff you would sign versus one you would
not, and nothing in this file can see the difference.
