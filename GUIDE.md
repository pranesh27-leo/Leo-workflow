# The leo guide

A complete walkthrough, from an empty repository to a commit you can still
understand a year later. No prior knowledge assumed.

**Contents**

1. [The problem](#1-the-problem)
2. [The mental model](#2-the-mental-model)
3. [Install](#3-install)
4. [Set up a repository](#4-set-up-a-repository)
5. [A complete change, step by step](#5-a-complete-change-step-by-step)
6. [When check complains](#6-when-check-complains)
7. [Reading the record later](#7-reading-the-record-later)
8. [Writing your first rule](#8-writing-your-first-rule)
9. [Picking up a change days later](#9-picking-up-a-change-days-later)
10. [Reference](#10-reference)
11. [What this does not do](#11-what-this-does-not-do)

---

## 1. The problem

You ask an AI for a feature. Ninety seconds later you have 500 lines across six
files. They look fine. The tests pass.

Two questions are now genuinely hard:

- **Did I get what I asked for?** Somewhere in those 500 lines might be a helper
  nobody needed, a renamed variable in an unrelated file, a config option
  invented on the spot. It all looks equally plausible, because it was all
  written in the same confident style.
- **Can I fix it at 3am when it breaks?** By then the chat is gone. The code is
  yours to maintain, and you never actually read it.

Reviewing the diff line by line does not scale, and "looks fine" is not review.
leo attacks both questions with the same trick: **make the agent account for
every hunk it wrote, and put that accounting where git will keep it.**

---

## 2. The mental model

Three files hold everything. All three are plain markdown you can read and edit.

| File | What it is | Written by |
|---|---|---|
| `.leo/plan.md` | what the change is *allowed* to be | you and the agent, before any code |
| `.leo/manifest.md` | one row per hunk: which task it serves, why, what breaks without it | the agent, after the code |
| commit message | the manifest, permanently | `leo commit`, run by you |

And one word you need: a **hunk** is a contiguous block of changed lines that
git reports as one unit. A 500-line change is typically 15–25 hunks. That is
why the manifest is readable when the diff is not — you are reading 20 rows
instead of 500 lines.

The loop:

```
   you          leo plan "..."      write down what it may be
   agent        (writes code)       one task at a time
   agent        leo scan            diff -> ~20 rows, judgement columns blank
   agent        (fills the rows)    which task, why, what breaks without it
   agent        leo check           rules, scope, budget, tests -- then STOPS
   you          leo commit "..."    you decide it is done. It refuses without a tty.
```

### Two documents, one authority

There are two pieces of prose in this system and they have different jobs, which
is worth knowing before you start editing either:

| | `.leo/workflow.md` | this guide |
|---|---|---|
| Read by | your agent, on demand | you, once |
| Contains | obligations — what the agent must do | behaviour — what the tools actually do, with real output |
| Lives in | your repository, yours to edit | the leo repository |
| If they disagree | it is right | it is stale |

So this page never tells you what your agent is instructed to do; it shows what
`leo` does when the agent has followed those instructions, and what you see when
it has not. That is the only division that survives you editing
`.leo/workflow.md` to suit your team — which you should.

---

## 3. Install

Requires git, bash, and a POSIX userland. Nothing else — no node, no jq, no
network calls.

```sh
git clone https://github.com/pranesh27-leo/Leo-workflow.git ~/leo
ln -s ~/leo/leo /usr/local/bin/leo
leo --version
```

```
leo 0.2.0
```

---

## 4. Set up a repository

From inside any git repository:

```sh
leo init
```

```
  install AGENTS.md
  install CLAUDE.md
  install .leo/workflow.md
  install .leo/rules/EXAMPLE.md
  install .leo/config
  update  .gitignore (.leo/plan.md)
  update  .gitignore (.leo/manifest.md)

ok   ready
  1. fill in AGENTS.md — delete every placeholder you do not need
  2. set TEST_CMD in .leo/config
  3. start a change: leo plan "<name>"
```

Nothing is overwritten without `--force`. What landed:

- **`AGENTS.md`** — your agent's standing instructions, loaded every session.
  Read natively by Codex, Cursor, Copilot, Gemini CLI, Aider and others. Keep it
  under 50 lines: every line costs you on every request. Fill in the real build
  and test commands, and delete the placeholders you do not need.
- **`CLAUDE.md`** — a one-line bridge (`@AGENTS.md`) so Claude Code reads the
  same file. Never keep two copies of your rules; they drift.
- **`.leo/workflow.md`** — **the authority on what your agent must do**, read by
  it on demand rather than every session. Anything this guide says about agent
  behaviour is a description of that file, not a second copy of it: when the two
  appear to disagree, `.leo/workflow.md` is right and this page is stale. Edit it
  freely — it is yours, and the agent follows your copy, not mine.
- **`.leo/config`** — set `TEST_CMD` here. Without it leo can check that the
  work was scoped honestly, but not that it works.
- **`.leo/rules/`** — empty for now. Section 8.

Then do the two-minute setup:

```sh
$EDITOR AGENTS.md                                  # real commands, real gotchas
echo 'TEST_CMD="python3 -m unittest -q test_app"' >> .leo/config
git add -A && git commit -m "chore: adopt leo"
```

> **Gitignore your build output first.** leo counts new files git can see as
> part of your change, exactly as `git status` does. If `__pycache__/`,
> `target/` or `dist/` is not ignored, it will show up in your manifest and
> inflate your budget.

---

## 5. A complete change, step by step

The example: a tiny JSON API with one endpoint. We are going to add rate
limiting. Every output below is real.

```
app.py            a request handler, checks an API key
test_app.py       one test
```

### Step 1 — Let the agent grill you

Say **"grill me on this, then plan it"** and describe the change. A well-behaved
agent now asks questions instead of writing code:

```
Before I plan this, five questions — my guess is in brackets, so "yes"
is a fine answer:

1. Limit per API key, or per IP? [per key — you already authenticate]
2. What limit? [60 requests/minute]
3. In-memory, or shared across processes via Redis? [in-memory; you run
   a single process today and Redis is a new dependency]
4. What should a limited client get back? [429 with a JSON error body]
5. Should limits differ per endpoint? [no — one global limit for now]
```

Answering five questions is the cheapest part of this whole loop, and it decides
how much the rest is worth. Everything downstream measures the diff against this
plan, so the plan is the resolution limit: against "improve rate limiting" every
hunk looks necessary, and nothing can ever come back marked unwanted. Against
"in-memory token bucket, 60/min, per key, no new dependencies", the Redis client
the agent adds out of habit has nowhere to hide.

Answer the questions. Let it ask another round if it needs one. Then:

```sh
leo plan "rate limiting"
```

```
ok   plan created: .leo/plan.md
  Fill it in, then have the agent work one task at a time.
```

The agent fills it in from your answers, and you read it before saying go:

```markdown
# Plan: rate limiting

## Goal
Cap each API key at 60 requests per minute, so one client cannot starve the rest.

## Non-goals
Does not touch authentication. Does not add per-endpoint limits. In-memory only
— no Redis, no shared state across processes.

## Wrong-change signal
If this needs a new dependency, we have misunderstood the problem.

## Tasks

| #  | Task                       | Files      | Est LOC | Status  |
|----|----------------------------|------------|---------|---------|
| T1 | token bucket, per key      | limiter.py | 35      | pending |
| T2 | reject over-limit requests | app.py     | 10      | pending |

## Budget
est: 45 LOC
```

Four things earn their place here:

- **Non-goals** are what stop scope creep. "Does not touch authentication" is
  what makes an auth change in the diff obviously wrong rather than arguably
  helpful.
- **Wrong-change signal** is a tripwire for the whole approach being off, not
  just the details.
- **Task IDs must be `T1`, `T2`, …** exactly. `leo check` matches on that format
  and will reject any ID in the manifest that is not in this table.
- **`est: 45 LOC`** is the budget. It does not need to be accurate — it needs to
  be *written down before the code exists*, so a 3× overshoot is visible.

### Step 2 — The agent builds it

Say **"implement T1"**. One task at a time, tests first. The agent moves the
Status column along: `pending` → `in-progress` → `done`.

Nothing in leo enforces this one — it is discipline, specified in
`.leo/workflow.md`. What you get for it is section 9: that column is the entire
memory of a long change, and it is the difference between resuming a dropped
session in ten seconds and reconstructing it from the diff.

### Step 3 — Split the diff into hunks

```sh
leo scan
```

```
ok   wrote .leo/manifest.md (7 hunks, 44 lines vs est 45)

Now fill in Task / Why / If deleted for every row, from the diff:
  git diff HEAD        <- read this, not your memory of what you wrote
  Never invent a task ID to make a hunk look justified. An honest '-' is
  the entire value of the exercise.
  Then: leo check
```

`.leo/manifest.md` now looks like this — the shell filled in the facts, and left
the judgement blank:

```markdown
| # | Hunk | Delta | Task | Why | If deleted |
|---|------|-------|------|-----|------------|
| 1 | `app.py:5` | +2/-0 |  |  |  |
| 2 | `app.py:8` | +1/-0 |  |  |  |
| 3 | `app.py:16` | +2/-0 |  |  |  |
| 4 | `app.py:21` | +1/-1 |  |  |  |
| 5 | `app.py:25` | +1/-1 |  |  |  |
| 6 | `test_app.py:9` | +14/-0 |  |  |  |
| NEW | `limiter.py` | +21 |  |  |  |

Budget: est 45 LOC / actual 44 LOC
Tests: <command> -- <paste the real output>
```

Seven rows. That is the whole change, and you can hold seven rows in your head.

### Step 4 — The agent fills in the three columns

This is the part that cannot be automated, because it is judgement. Three
columns, and what you should get out of each when you read the finished table:

| Column | What you learn from it |
|---|---|
| **Task** | whether anyone asked for this hunk. `-` means nobody did |
| **Why** | whether the agent understood *why* the task needs this, or is just describing its own code back to you |
| **If deleted** | whether the hunk is load-bearing |

`If deleted` is the column that does the work, because it is a necessity test
rather than an opinion. "Nothing" is a confession, and it is one the agent is
instructed to make rather than dress up.

Here is the filled table. Note rows 4 and 5:

```markdown
| # | Hunk | Delta | Task | Why | If deleted |
|---|------|-------|------|-----|------------|
| 1 | `app.py:5` | +2/-0 | T2 | imports the limiter | T2 cannot call it |
| 2 | `app.py:8` | +1/-0 | T2 | one limiter shared by the process | each request gets a fresh bucket, nothing is limited |
| 3 | `app.py:16` | +2/-0 | T2 | returns 429 once the bucket is empty | the limit is computed but never enforced |
| 4 | `app.py:21` | +1/-1 | - | renamed a local while I was in the file | nothing |
| 5 | `app.py:25` | +1/-1 | - | renamed a local while I was in the file | nothing |
| 6 | `test_app.py:9` | +14/-0 | T1 | proves the bucket allows 60 and blocks the 61st | the limit is unverified |
| NEW | `limiter.py` | +21 | T1 | the fixed-window bucket itself | no limiting at all |
```

The agent renamed `payload` to `encoded_payload` in a method nobody asked it to
touch. Harmless, plausible, and completely unrequested — the exact thing that is
invisible in a 500-line diff and obvious in a table.

### Step 5 — Check

```sh
leo check
```

```
rules
  no rules yet — write one the next time you fix a real bug

manifest
ok   every hunk reviewed
ok   every task ID is one the plan declared
warn 2 hunk(s), 2 lines, serve no task — revert, promote or split

budget
ok   est 45 LOC / actual 44 LOC

tests
ok   python3 -m unittest -q test_app
       Ran 3 tests in 0.000s

       OK

ok   all checks passed
```

Checks pass, and you are still told the truth: two hunks serve no task. The
agent will arrive with a recommendation for each — `.leo/workflow.md` requires
one — but the disposal is yours: put it back, admit it into the plan as real
work, or let it go out as its own commit. Reverting is the right default, and
the agent knows that, which is why anything it argues to keep is worth reading.

Here the call is revert. After reverting the rename and rescanning:

```
manifest
ok   every hunk reviewed
ok   every task ID is one the plan declared

budget
ok   est 45 LOC / actual 40 LOC

tests
ok   python3 -m unittest -q test_app
       Ran 3 tests in 0.000s

       OK

ok   all checks passed
```

Five rows, all of them accounted for.

> **The `Tests:` line is written by leo, not by the agent.** `leo check` runs
> your suite and records what actually happened, so a commit can never carry a
> test result nobody observed. If the agent left a placeholder there and no test
> command is configured, check fails.

### Step 6 — You commit

The agent stops here. It shows you the command and waits:

```
Checks pass. 3 files, +40 lines, every hunk mapped to T1/T2.
Ready when you are:

    leo commit "api: cap each key at 60 requests per minute"
```

If it tries to run that itself, it gets turned away:

```
ERR  leo commit needs a human at a terminal

If you are an agent: do not commit. Show the developer what you would run,
and stop there. They decide when the change is done.
```

When *you* run it:

```
about to commit
  api: cap each key at 60 requests per minute
  3 file(s), 40 lines
commit? [y/N] y
[main 989f945] api: cap each key at 60 requests per minute
 3 files changed, 40 insertions(+)
 create mode 100644 limiter.py
ok   committed 989f945
```

If any hunk in the commit still serves no task, the prompt says so before you
answer — a last look at what you are about to make permanent.

---

## 6. When check complains

Four failures, what each means, and what to do.

### "N hunk(s) not reviewed"

```
ERR  7 hunk(s) not reviewed — every row needs Task, Why and If deleted
```

The table is still blank. The agent ran `leo scan` and skipped the thinking.
Send it back to fill in the columns — from `git diff`, not from memory.

### "T3 is not a task in the plan"

```
ok   every hunk reviewed
ERR  T3 is not a task in the plan — never invent a task ID to justify a hunk
```

This is the important one. The agent labelled its drive-by rename `T3` — a task
that does not exist — because a filled-in row looks better than an honest `-`.

`leo check` collects every task ID in the plan's table and every ID used in the
manifest, and fails on any that is not in both. It is the only check that
catches an agent being *dishonest* rather than incomplete, and it exists because
inventing a plausible justification is the one move that would otherwise pass
every other check cleanly.

Your call, either way: the work was needed (add a real task to the plan) or it
was not (mark it `-` and revert).

### "est N LOC, actual M LOC (over 2x)"

```
ERR  est 45 LOC, actual 190 LOC (over 2x) — re-read the request before reviewing
```

This one is not about the code. An overshoot this large almost always means the
requirement was misread, not that the work was genuinely bigger — so the useful
next move is re-reading your original request, not the diff. Grinding carefully
through 190 lines is a worse use of an afternoon than finding out in the first
five minutes that you are building the wrong thing.

### A rule fired

```
rules
ERR  WALL-CLOCK violated
       ./limiter.py:13:        now = time.time()
```

A mistake you have already fixed once has come back. Section 8.

---

## 7. Reading the record later

This is what all of it was for. Six months on, `git log`:

```
commit 989f945112573f65925d8b58949cfa29eab40431
Author: dev <dev@example.com>
Date:   Thu Sep 3 23:48:55 2026 +0530

    api: cap each key at 60 requests per minute

    Goal: Cap each API key at 60 requests per minute, so one client cannot starve the rest.

    | # | Hunk | Delta | Task | Why | If deleted |
    |---|------|-------|------|-----|------------|
    | 1 | `app.py:5` | +2/-0 | T2 | imports the limiter | T2 cannot call it |
    | 2 | `app.py:8` | +1/-0 | T2 | one limiter shared by the process | each request gets a fresh bucket, nothing is limited |
    | 3 | `app.py:16` | +2/-0 | T2 | returns 429 once the bucket is empty | the limit is computed but never enforced |
    | 4 | `test_app.py:9` | +14/-0 | T1 | proves the bucket allows 60 and blocks the 61st | the limit is unverified |
    | NEW | `limiter.py` | +21 | T1 | the fixed-window bucket itself | no limiting at all |

    Budget: est 45 LOC / actual 40 LOC
    Tests: `python3 -m unittest -q test_app` -- passed, 2026-09-03 18:18 UTC

    Assisted-by: Claude Code
```

Production is throwing 429s at a customer who should be under the limit. You
find the line:

```sh
git blame -L 16,18 app.py
```

```
989f9451 (dev 2026-09-03 23:48:55 +0530 16)         if not LIMITER.allow(key):
989f9451 (dev 2026-09-03 23:48:55 +0530 17)             return self.reply(429, {"error": "rate limit exceeded"})
^5a704dd (dev 2026-09-03 23:48:10 +0530 18)         return self.reply(200, {"account": KEYS[key]})
```

```sh
git show 989f9451
```

And row 2 tells you the limiter is one instance shared by the process — so if
you are now running four workers, each has its own bucket and the effective
limit is 4×60. Nobody had to remember that. Nobody had to ask an AI. It is in
git, next to the code, forever.

This is why the manifest goes in the commit message rather than in git notes, a
side file, or a wiki: those all require someone to know they exist. `git log`
and `git blame` are already in your fingers.

---

## 8. Writing your first rule

Rules are how a lesson outlives the conversation that learned it. Both you and
your agent can write them — `.leo/workflow.md` tells the agent when to reach for
one; this is what you need to know to read, debug and write them yourself.

The test for whether something should be a rule: **can a shell command detect
it?** If yes, it runs on every `leo check` from then on, costs no tokens, and is
still working long after everyone has forgotten the incident.

A real one. The rate limiter used `time.time()` — the wall clock — which jumps
when NTP corrects it, so a window could end early. Fixed once. To make sure it
stays fixed, `.leo/rules/WALL-CLOCK.md`:

````markdown
# MUST NOT measure elapsed time with the wall clock

MUST NOT: use `time.time()` for durations, timeouts or rate-limit windows. It
jumps when NTP corrects the clock, so a window can end early or never end.
Use `time.monotonic()`.

Learned from: the limiter let a key through 3x its quota during a DST change.

## Verify

```sh
! grep -rn 'time\.time()' --include='*.py' .
```
````

The `## Verify` block is a shell command that must **exit 0 when the rule holds**
and non-zero when it is violated. The leading `!` inverts grep: no matches means
the rule holds.

Someone reintroduces it months later:

```
rules
ERR  WALL-CLOCK violated
       ./limiter.py:13:        now = time.time()
```

Fixed:

```
rules
ok   WALL-CLOCK
```

Two things make rules worth the trouble:

- **They cost nothing.** No tokens, about a second. You can have fifty.
- **Anyone can debug one.** It is a shell command in a markdown file. Paste it
  into your terminal and see for yourself. Compare that to a lesson that lives
  in a prompt somewhere and quietly stops applying.

Rules live in `.leo/rules/` and are committed, so they are shared by the team
and enforced identically for every agent anyone uses.

If the mistake cannot be shell-detected — "used the wrong algorithm", "did not
consider this edge case" — put it in the commit message instead. Not everything
compresses to a grep, and pretending otherwise produces rules that fire on
innocent code until someone deletes them all.

---

## 9. Picking up a change days later

Nothing about this workflow lives in the chat. A dropped connection, a closed
laptop, a week off, a context window that filled up — none of it costs you
anything, because the state is three files on disk.

```sh
leo plan
```

```
| #  | Task                        | Files      | Est LOC | Status      |
|----|-----------------------------|------------|---------|-------------|
| T1 | per-endpoint config table   | limits.py  | 25      | done        |
| T2 | look the limit up per route | app.py     | 15      | in-progress |
| T3 | document the defaults       | README.md  | 10      | pending     |

1 of 3 done  |  in progress: T2
```

Then:

```sh
git diff HEAD          # the code you already wrote, still sitting there
cat .leo/manifest.md   # the review table, as far as it got
```

Hand those to a fresh session — "read .leo/plan.md and continue T2" — and it
picks up exactly where the last one stopped.

**This works only if the Status column is honest** — which is exactly the
discipline `.leo/workflow.md` imposes in step 2, and the reason it is worth
imposing. An agent that batches its status updates to the end of a session it
never reaches leaves you a plan that lies, and the next session either redoes T2
or skips it. If you ever find yourself resuming into a wrong state, that is the
line to check.

**One limit worth knowing.** `.leo/` is gitignored by default, so this survives
reboots and weeks away but is local to one machine. If you need a change to
survive across machines, or to be visible to a teammate, drop `.leo/plan.md`
from `.gitignore` and commit it. The default is local because the plan ends up
in the commit message anyway, and tracking it records the same intent twice.

---

## 10. Reference

### Commands

| Command | Who runs it | What it does |
|---|---|---|
| `leo init [--force]` | you, once per repo | installs AGENTS.md, CLAUDE.md, `.leo/` |
| `leo plan "<name>"` | you, per change | writes the plan skeleton |
| `leo plan` | either | shows the plan and where it stands |
| `leo scan [base]` | agent | diff → `.leo/manifest.md`, one row per hunk |
| `leo check` | agent | rules, unreviewed hunks, invented IDs, budget, tests |
| `leo commit "<subject>"` | **you only** | commits with the manifest in the message |
| `leo help` | either | the short version of this document |

`leo scan main` reviews against a branch instead of `HEAD`; `leo check` then
measures against the same base automatically, so the two can never disagree.

### Files

| Path | Committed? | What it is |
|---|---|---|
| `AGENTS.md` | yes | standing instructions, every session, keep under 50 lines |
| `CLAUDE.md` | yes | one-line bridge so Claude Code reads AGENTS.md |
| `.leo/workflow.md` | yes | **the agent's instructions — the authority** |
| `.leo/rules/*.md` | yes | one lesson per file, each with a shell check |
| `.leo/config` | yes | `TEST_CMD` |
| `.leo/plan.md` | no | current change |
| `.leo/manifest.md` | no | current review table |

### Config

`.leo/config` is plain shell:

```sh
TEST_CMD="go test ./..."
```

That is the only setting. If you find yourself wanting more, the tool is
probably not the right place for it.

### Exit codes

`0` success · `1` a check failed · `2` `leo commit` refused (no human present).

---

## 11. What this does not do

Being clear about the edges is what makes the rest trustworthy.

**It is a guardrail, not a sandbox.** `leo commit` refuses without a terminal,
but `LEO_YES=1` exists for CI and anything that can run a shell can set it. The
value is that the default path hands the decision back to you, and that the
workflow says plainly whose call it is.

**It cannot make an agent think.** leo catches a *lie* — an invented task ID, a
test result nobody observed, a hunk left unaccounted for. It cannot catch a
*shrug*: a `Why` that reads "adds a function" is uninformative but passes. That
is what your eyes on twenty rows are for. Twenty rows is a realistic thing to
ask of a human; 500 lines is not.

**A new file is one row.** git has no hunks to split it by, so scope creep
*inside* a brand-new file is not isolated for you — `limiter.py` above is one
row for 21 lines. Read new files properly.

**The budget is a smoke alarm, not a spec.** 2× over is a signal that the
requirement was misread. It is deliberately crude, and it is not a code quality
measure.

**It does not review code.** No style opinions, no architecture advice, no
security scanning. It answers "is this the change we agreed on, and will I
understand it later" — nothing else. Use your normal review tools for the rest.
