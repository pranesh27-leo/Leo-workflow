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

> Everything in this guide is described against a small example. For the same
> workflow run end to end against a real upstream project — a real defect in
> `pallets/click`, checked against its own 1990-test suite, including the three
> times leo rejected the change before it landed — see **[DEMO.md](DEMO.md)**.

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
  update  .gitignore (.leo/session)

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

### Step 2 — The agent gives each task a file

Say **"make the tasks"**. For every row of the plan's table:

```sh
leo task T1
```

That writes `.leo/tasks/T1.md` — a skeleton the agent fills in, the same way
`leo plan` writes a plan skeleton for you to fill in:

```markdown
# T1: token bucket, per key

Files: api/limit.go
Est:   60 LOC

## Done when
`go test ./api -run TestBucket` passes, and a 61st request in a minute gets 429.

## To-do
- [ ] write the test from "Done when" above — the spec, not the implementation
- [ ] run it, watch it FAIL, and confirm it failed for the reason you expect
- [ ] implement the smallest thing that makes it pass
- [ ] run it, watch it pass
- [ ] set T1 to done in .leo/plan.md

## Notes
Rejected a sliding window: needs a second timestamp per key and the plan's
budget does not cover the storage change.
```

That to-do is the TDD capability doing something visible — with `--tdd off` you
get two blank placeholders and your own order instead. Section 11 covers the
switch.

**Where the statuses live.** The plan's `Status` column says whether a task is
done. The task file says what is left *inside* it. Neither restates the other,
and a task file with a `Status:` field is a bug — it is the copy nobody
updates.

Nothing blocks on any of this. `leo check` never reads a task file and an
unticked box fails nothing. It is the agent's working memory, and it exists so
that a session ending mid-task costs you nothing:

```sh
leo task
  T1    3/5     in-progress   token bucket, per key
  T2    0/4     pending       429 response and Retry-After
```

### Step 3 — The agent builds it

Say **"implement T1"**. One task at a time, tests first. The agent moves the
Status column along: `pending` → `in-progress` → `done`, and ticks the boxes in
the task file as it goes.

Nothing in leo enforces this one — it is discipline, specified in
`.leo/workflow.md`. What you get for it is section 9: that column is the entire
memory of a long change, and it is the difference between resuming a dropped
session in ten seconds and reconstructing it from the diff.

### Step 4 — Split the diff into hunks

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

### Step 5 — The agent fills in the three columns

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

### Step 6 — Check

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

### Step 7 — You commit

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
| `leo session` | you | shows the mode and what it declares |
| `leo session --mode <name>` | you | sets it: coding, debugging, learning, review, exploration |
| `leo session --report` | either | where this change stands, end to end |
| `leo install` | you | what is installed and what is not |
| `leo install <name>` | **you only** | installs one. Shows the command, asks first. |
| `leo install --all` | **you only** | installs everything this session declares |
| `leo session --clear` | you | ends it |
| `leo plan "<name>"` | you, per change | writes the plan skeleton |
| `leo plan` | either | shows the plan and where it stands |
| `leo task T1` | agent | gives one plan task its own file and to-do, or shows it |
| `leo task` | either | every task, its to-do progress and its plan status |
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
| `.leo/integrations/*.sh` | yes | tools your repo adds, one file each |
| `.leo/tools/*.md` | yes | one per capability: how to use it, what it needs |
| `.leo/config` | yes | `TEST_CMD` |
| `.leo/session` | no | current mode, if you set one |
| `.leo/plan.md` | no | current change |
| `.leo/tasks/*.md` | no | one per task: "Done when", a to-do, notes |
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

## 11. Declaring the session

Optional, and it is the one part of leo that does not check anything.

Your agent does not read your code directly. By the time it gets there, several
other tools may have had a turn: a semantic index deciding which symbols to show
it, a filter trimming your test output, a compressor shortening what it
remembers, a ruleset telling it to write less prose. Each is defensible on its
own. Together they decide what the agent could see when it wrote the change —
and the diff does not record any of it.

`leo session` records it.

```sh
leo session --mode debugging
```

```

leo session
  Mode: debugging

code intelligence
  Serena        ON
  Code graph    ON

efficiency
  RTK           ON
  Headroom      OFF
  Ponytail      OFF
  Caveman       OFF

practice
  TDD           ON

engineering controls
  Plan          ON   always
  Task IDs      ON   always
  Manifest      ON   always
  Rules         ON   always
  Tests         ON   always
  Human commit  ON   always

dependencies
  Serena        MISSING
      instructions: .leo/tools/serena.md
      uv tool install -p 3.13 serena-agent
      claude mcp add serena -- serena start-mcp-server --context claude-code --project "$(pwd)"
  Code graph    MISSING
      instructions: .leo/tools/graph.md
      curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash
      the installer registers the MCP server with Claude Code itself
  RTK           MISSING
      instructions: .leo/tools/rtk.md
      brew install rtk        (or: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh)
      rtk init -g             installs the auto-rewrite hook
  TDD           MISSING
      instructions: .leo/tools/tdd.md
      set TEST_CMD in .leo/config — that is the whole install
        TEST_CMD="go test ./..."   TEST_CMD="npm test"   TEST_CMD="pytest -q"

warn 4 enabled capability(s) not installed — leo works without them
  install one above, or drop it here: leo session --<name> off
  leo does not install these. Declaring one does not switch anything on.
```

### The modes

| Mode | For | What it changes |
|---|---|---|
| `coding` | building a planned change | everything on, including the reducers and TDD |
| `debugging` | finding out why something is wrong | semantic reducers off, TDD on |
| `learning` | understanding code you did not write | reducers off, code graph on, TDD off |
| `review` | reading a change someone else made | reducers on, minimisation off, TDD off |
| `exploration` | surveying unfamiliar ground | reducers off, code graph on, TDD off |

The line that runs through all five: **structural filtering stays on, semantic
filtering comes off when detail is the point.** Dropping progress bars and
deduplicating repeated log lines is safe in any mode. A model deciding which
lines mattered is not, because during debugging the thing that matters is
routinely the thing that looks like noise.

**TDD is the odd one out**, and deliberately so. It is not a tool mediating
what the agent sees — it says what order the work is done in, so it gets its
own `practice` heading. It is ON in `coding` and `debugging` (a bug reproduced
by a failing test first is the same discipline) and OFF in the three modes that
write no code. "Installed" means this repo has a `TEST_CMD` in `.leo/config`,
because without one there is nothing to watch fail.

What it switches is the **order**, and only the order. With `--tdd off` you may
write the test afterwards — you may not skip it. `leo check` runs `TEST_CMD`
and records the result in the manifest either way, and no mode can turn that
off. It is an engineering control, and those are not on this list.

Override any one of them, and the override is marked as yours:

```sh
leo session --mode debugging --caveman on
```

Setting a new mode clears your overrides. Carrying a hand-set capability across
a mode change is exactly how someone ends up debugging with the prose
compressor still on.

### The tools it can name

Seven capabilities, each with an adapter. An adapter is a file in
`core/integrations/` that answers three questions and does nothing else:

```sh
serena_present() { command -v serena >/dev/null 2>&1; }   # installed?
serena_hint()    { ... }                                  # how to install it
serena_advice()  { ... }                                  # what to do with it
```

That is the entire integration surface. No installing, no launching, no
wrapping, no writing outside `.leo/`. Adding one is the third extension point,
and `.leo/rules/ADAPTER-CONTRACT.md` checks that a new one is reachable.

| Capability | What it is for | Where it comes from |
|---|---|---|
| Serena | symbols, references, semantic edits | MIT, `oraios/serena` |
| RTK | shell output filtering, structural | Apache-2.0, `rtk-ai/rtk` |
| Headroom | context compression, semantic | Apache-2.0, `headroomlabs-ai/headroom` |
| Ponytail | write less code | MIT, `DietrichGebert/ponytail` |
| Caveman | write less prose | MIT skill, BSL-1.1 engine, `JuliusBrussee/caveman` |
| Code graph | call chains, blast radius | MIT, `DeusData/codebase-memory-mcp` |

Three things the dependencies block will tell you that are worth knowing before
you install anything:

- **RTK's hook rewrites the agent's Bash calls, and the agent runs `leo check`
  through Bash.** A compressed check is a check whose failures the agent may not
  read — and `leo check` writes the test result it just observed into the
  manifest, so a truncated run becomes a recorded claim about tests nobody saw.
  Exclude `leo` in `~/.config/rtk/config.toml`. The RTK adapter prints the
  three lines you need.
- **`headroom wrap claude` installs Serena itself**, at user scope in
  `~/.claude.json`, and leaves it there until you unwrap. If Serena is also on,
  you have two owners of one MCP entry. leo says so when both are enabled.
- **RTK and Headroom both reduce what the agent reads**, and `coding` and
  `review` turn both on. RTK filters shell output structurally; Headroom
  compresses the context semantically and sees RTK's output already dense, so
  the second pass buys little on that buffer. `leo session` prints a
  **conflicts** block whenever both are declared — whether or not either is
  installed, because that is a property of the policy, not of your machine.
- **The code graph is the one that took a second try.** GitNexus is the
  best-known tool here and is PolyForm Noncommercial — most people reading this
  write code at work, and leo will not default its users into a licence they
  cannot use. `codebase-memory-mcp` is MIT, a single static binary with no
  runtime of its own, and its `detect_changes` maps a git diff to the symbols it
  affects — which is the same question `leo scan` asks of a diff from the other
  end. A licence is a technical constraint here, not a footnote.

If a tool is not installed, leo says so and carries on. Nothing here can fail a
check, and `leo check` on a machine with none of them installed behaves exactly
as it does today — there is a test for that too.

### The instruction files

Every capability leo ships with installs one file into your repository:

```
.leo/tools/serena.md    graph.md    rtk.md    headroom.md
           ponytail.md  caveman.md  tdd.md
```

`leo session` prints the path beside each capability that is ON — whether it is
installed (you are about to use it) or MISSING (you need to know what it wants
before you install it). `.leo/workflow.md` tells the agent to read that file
before using the tool, and to use nothing that is not both ON and installed.

They are **copies**, installed by `leo init` like `.leo/workflow.md` is, so your
team can amend them. `leo init --force` restores leo's version.

Two of them carry a standing order rather than advice. The code graph is
**CLI only** — its MCP wire returns `Cannot read properties of undefined` on
every call, and the CLI returns the same data, so an agent that only knows the
MCP names concludes the tool is dead. Caveman is **skill only** — leo uses the
MIT skill and never the cloud gateway, so there is no account, no
`CAVE_API_KEY`, and nothing to configure.

**Each fact lives in exactly one file.** The prerequisites, the failure
signatures and the things not to do are in `.leo/tools/<name>.md` and nowhere
else; the adapter carries the install command and one line at the terminal, and
this guide carries the index below and no facts at all. `.leo/rules/TOOL-DOC.md`
enforces the first half of that, and `t/smoke.sh` asserts the second.

### When a tool misbehaves

Symptoms that look like a broken tool and are not. Each one is answered in
full in the file named — this table deliberately restates none of it:

| What you see | Read |
|---|---|
| `Cannot read properties of undefined (reading 'properties')` | `.leo/tools/graph.md` |
| `passing raw JSON is deprecated`, and flags do not work | `.leo/tools/graph.md` |
| Caveman stays MISSING after a successful install | `.leo/tools/caveman.md` |
| `npx caveman` cannot determine an executable | `.leo/tools/caveman.md` |
| a skill asks you for a gateway URL or an API key | `.leo/tools/caveman.md` |
| `Unknown language 'javascript'` | `.leo/tools/serena.md` |
| `health-check` says a language server is not installed | `.leo/tools/serena.md` |
| `serena project health-check` rejects `--project` | `.leo/tools/serena.md` |
| `tree command not found` from `rtk tree` | `.leo/tools/rtk.md` |
| `leo check` output looks truncated | `.leo/tools/rtk.md` |
| Serena configured twice, at user scope | `.leo/tools/headroom.md` |
| TDD reads MISSING and you cannot see why | `.leo/tools/tdd.md` |

### Installing them

```sh
leo install              # what is installed, and what is not
leo install serena       # one
leo install --all        # everything this session declares
```

```
install serena
  leo will run this. It is not leo's code, and leo has not audited it:

      uv tool install -p 3.13 serena-agent
      claude mcp add serena -- serena start-mcp-server --context claude-code --project '/home/you/repo'

run it? [y/N]
```

Three properties, and they are the reason this is a separate command rather
than something `leo session` does for you:

- **It shows you the command before it runs it.** Almost everything here is
  somebody else's installer, fetched over the network, and leo has not read it.
  You approve the actual string, chosen for your machine — `leo install rtk`
  prints `brew install rtk` if you have Homebrew and the `curl | sh` line if
  you do not, rather than offering you a menu of what might happen.
- **It refuses without a human at a terminal**, exactly as `leo commit` does.
  An agent that hits this gets told to show you the command and stop. Deciding
  what goes on your machine is not its call.
- **Nothing else in leo installs anything.** `leo session` declares,
  `leo scan` enumerates, `leo check` verifies, and all three work on a machine
  with none of these tools present. There is a test asserting that none of them
  ever emits an install command. That is what makes an optional dependency
  actually optional, and confining it to one command is how it stays true.

`leo install --all` only installs what the current session declares. A tool the
mode turns off does not get installed, because the mode already decided that.

### Teaching leo a tool it does not know

Six capabilities ship with leo. Yours will not be one of them.

Drop a `<name>.sh` into `.leo/integrations/`. leo sources every `*.sh` there,
the file name becomes the capability, and `leo session --<name> on` and
`leo install <name>` start working. No registry, no manifest file, no
`leo plugin add`. `.leo/integrations/README.md` — installed by `leo init` —
holds the full template.

```sh
# .leo/integrations/vitals.sh
vitals_present() { command -v vitals >/dev/null 2>&1; }          # required
vitals_hint()    { say "npx --yes skills add chopratejas/vitals"; }  # required
vitals_install() { say "npx --yes skills add chopratejas/vitals"; }  # optional
vitals_default() { case "$1" in review|debugging) printf 'on' ;; *) printf 'off' ;; esac; }
vitals_advice()  { say "rank hotspots by ROI before picking what to fix"; }
vitals_label()   { printf 'Vitals'; }
```

```
extensions
  Vitals        ON
```

Two things worth knowing:

- **An adapter must define functions and nothing else.** leo sources it on
  every command, so anything it does at the top level, it does on every
  `leo check`. leo parses each repository adapter before loading it and skips
  one that does not compile — a broken adapter prints a warning and changes
  nothing else, and there is a test that says so. That guard is the line
  between an extension point and a plugin framework, and if it ever stops
  holding, this feature should come back out.
- **`.leo/integrations/` is committed.** A capability your team depends on
  arrives with the repository, not in somebody's setup notes. It is also
  repository code that leo runs, the same as `.leo/config` and the `## Verify`
  block in every rule — read an unfamiliar repo's `.leo/` before running leo in
  it, the same as you would read its Makefile.

### The report

```sh
leo session --report
```

```
leo session report
  Change        session policy
  Mode          debugging
  Declared      serena, graph, rtk
  Not installed serena, rtk
  Tasks         12 of 14 done  |  in progress: T12
  Change size   17 file(s), 733 lines
  Manifest      18 hunk(s), 18 reviewed, 0 serving no task
  Tests         `bash t/smoke.sh` -- passed, 2026-09-04 05:11 UTC
  Approval      PENDING — leo commit is yours

  no token figures here on purpose: the tools above measure different
  things over overlapping buffers, and summing them would be fiction.
```

Every line is read back from something that already exists — the plan, the
session file, git, the manifest. Nothing is stored to make this printable, and
nothing here is a second source of truth.

The last line is the point. `Approval: PENDING` is the only status leo will ever
print for a change it can see, because deciding a change is done is not
something a tool gets to do.

### What it does not do

**It does not install anything.** Serena, RTK and the rest are yours, set up
once, outside leo. leo has no runtime dependency on any of them and never will:
`git`, `bash` and a POSIX userland is the whole requirement, and a session file
does not change that. Declaring a capability leo cannot act on says so on the
line rather than looking enabled.

**It does not gate anything.** `leo check` behaves identically with and without
a session — there is a test that says so. The one thing a session adds to a
failing check is a single line naming the mode, because a check failing while
the session still says `coding` is the moment you realise you have been
debugging for an hour with the reducers on.

**It cannot turn a control off.** The engineering controls are listed above
because they are the point of the tool, not because they are settings. There is
no key for them in `.leo/session` and no flag for them on the command line;
they live in the code that runs them. An optimisation may change what the agent
sees. None of them gets to change what leo checks.

**It does not report token savings.** Every tool named above measures a
different thing against a different denominator, over buffers that overlap.
Adding those numbers together produces a figure that is simply false, and leo
would rather report nothing than that.

Where it ends up is the commit message, next to `Assisted-by:`:

```
Session: debugging (caveman=on)
Assisted-by: Claude Code
```

Which is the same bargain as the rest of leo: in six months the diff will not
tell you the agent was working from compressed output when it wrote that line.
`git show` will.

---

## 12. What this does not do

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
