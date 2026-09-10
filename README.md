# leo

A workflow for working with coding agents, in ~500 lines of POSIX shell.

It exists to answer one question: **when 500 lines arrive that you did not
type, how do you know they are the right 500 lines — and how do you debug them
at 3am without an AI?**

## The seven ideas

1. **The agent grills you before it plans.** It asks questions in rounds — each
   with a recommended default — and stops after each round instead of running
   ahead. There is no limit on how many: it keeps going until you and it share
   the same understanding and you say so. The grill itself is Matt Pocock's
   `grill-me` skill, vendored unmodified into `.leo/skills/`. Out of that comes `.leo/plan.md`: the goal, the non-goals, numbered
   tasks `T1`, `T2`, …, and a LOC estimate. You build the plan together, and it
   is specific enough to measure against. A vague plan justifies anything.
   Then `leo task T1` gives each of those numbered tasks its own file: what
   *done* looks like, a to-do the agent ticks as it goes, and the decisions the
   code cannot record. A session that ends mid-task costs nothing.
2. **A manifest makes a diff reviewable.** `leo scan` turns the diff into one
   row per hunk. The agent fills in *which task this serves*, *why*, and *what
   breaks if it is deleted*. You read ~20 rows and spot-check the risky ones.
   `leo check` then rejects any task ID the plan never declared, so the agent
   cannot invent a justification, and reports the unwanted work in lines:
   `2 hunk(s), 47 lines, serve no task`. That is your answer to "which of these
   500 lines did I not ask for?"
3. **You commit, not the agent — and only once.** A cycle ends at
   `leo record`, which files the commit message that cycle earned and lands
   nothing. Run cycle one as many times as the change needs; `leo commit` then
   folds every record into a single commit, refuses to run without a human at
   a terminal, and is yours. Having just written the code, the agent is the
   last party that should decide the code is done — and it was being asked
   that question once per cycle, when the honest answer only exists once.
4. **The record belongs in the commit message.** Not in git notes, not in a side
   file, not in a chat log. `git blame` → `git show` and you get the reason a
   line exists, from git alone, forever.
5. **A lesson becomes a shell command.** Each `.leo/rules/*.md` holds a check
   that exits non-zero when a known mistake reappears. It runs on every
   `leo check`, costs no tokens, and outlives the session that learned it.
6. **The tool switches are switches, and you see them flip.** Your agent does
   not read your code directly — a semantic index, an output filter and a
   context compressor may each have had a turn first, and the diff records none
   of it. `leo session --mode debugging` declares which of them this work wants,
   and it is enforced rather than merely recorded: before using one the agent
   runs `leo use serena`, which **prints what it is using for you to see** and
   logs it in the same action, so what you read and what `leo check` reads
   cannot drift apart. A tool that is ON and never used fails the check. A tool
   that is OFF is refused at the moment of use, and the attempt is recorded so
   ignoring the refusal fails too. leo installs none of them, and none of them
   can turn a check off. Each ships an instruction file — `.leo/tools/<name>.md`
   — pointed at when the tool is used rather than loaded up front, so seven
   tools cost a session that needed one nothing.

   leo cannot force an agent to call a tool; nothing can, from a shell. What it
   can do is refuse to pass until the evidence is there, which is the same trade
   the grill has always made.

7. **The author does not review the change.** A commit ends the first cycle and
   starts a second one, in a new session: `leo review` opens a review of the
   commit that just landed and *cannot edit your code* — there is no stage in it
   that writes to the source tree. It arrives briefed rather than blank, because
   `leo commit` already put the goal, the whole manifest and the session into
   the commit message, and the plan and task files still hold the non-goals and
   the decisions the grill settled. A reviewer who does not know what was asked
   for can only check the code against itself, which is how a change that is
   internally consistent and completely wrong passes. A `blocker` holds the
   review open until you fix it — as a new first cycle — or waive it in writing.

**New here? [Read the guide](GUIDE.md)** — a step-by-step walkthrough of one
complete change, with real output at every step.

**Want to see it work first? [Read the demo](DEMO.md)** — one recorded session
against `pallets/click`, fixing a real defect in it, checked against click's
own 1990-test suite. Including the three times leo rejected the change before
it landed.

## Install

```sh
ln -s "$PWD/leo" /usr/local/bin/leo
cd ~/your-repo && leo init
```

## Use

```sh
leo session --mode coding       # optional: what kind of work this is
leo install --all               # optional: get what that mode declares
leo plan "rate limiting"        # after the agent has grilled you
leo task T1                     # each task gets a file and a to-do
                                # ...the agent builds it, one task at a time
leo scan                        # split the diff into hunks
                                # ...the agent fills in Task / Why / If deleted
leo use serena                  # the agent says which tool it is using, and logs it
leo check                       # rules, hunks, tools, TDD, budget, tests
leo record "api: rate limit"    # the cycle's message, filed. Nothing in git yet.
                                # ...repeat cycle one for the next part
leo commit                      # you run this one. It refuses without a tty,
                                # and lands every record as one commit.

# then, in a NEW session — cycle two, which the commit above asks for
leo session --mode review
leo review                      # briefed from the commit cycle one just wrote
                                # ...the agent files findings against
                                #    .leo/review/STANDARDS.md. It cannot edit code.
leo review --close              # yours too. No open blocker, and a real verdict.
```

## Picking up a change days later

Nothing lives in the chat, so a dropped connection, a closed laptop or a week
away costs nothing:

```sh
leo plan               # the plan, plus "2 of 5 done | in progress: T3"
git diff HEAD          # the code you already wrote, still sitting there
cat .leo/manifest.md   # the review table, as far as it got
```

The Status column in the plan is the whole memory of a long change. `.leo/` is
gitignored by default, which keeps it local and disposable — if you need a
change to survive across machines or be visible to teammates, drop
`.leo/plan.md` from `.gitignore` and commit it.

## Layout

```
leo                dispatch: a command is a file in core/cmd/, no registry
core/lib.sh        every shared helper, one screen
core/cmd/*.sh      one file per command, readable top to bottom
core/integrations/ the tools leo ships with: detect, hint, install, advise
templates/         what `leo init` copies into a repository
.claude/           a Claude Code front door for cycle two: a `/review` command
                   and a read-only reviewer subagent. Copy them into your own
                   repo or ignore them — leo itself is agent-agnostic, and
                   nothing in `core/` knows they exist.
```

## Extending it

There are exactly three extension points, and none requires touching the code:

- **A new check** is a new file in `.leo/rules/`.
- **A new command** is a new file in `core/cmd/`. `leo <name>` finds it.
- **A new tool** is a new file in `.leo/integrations/`, committed with your
  repo, defining two required functions — is it installed, how do you install
  it — and up to four optional ones. `leo session --<name> on` and
  `leo install <name>` then work for it. leo parses an adapter before it loads
  it and skips one that does not compile, because nothing a repository adds may
  be able to break `leo check`.

If a change needs more machinery than that, it probably does not belong here.
Every abstraction in this tool has to earn itself against a simple rule: you
must be able to read the whole thing in one sitting.

## Using it, day to day

Two cycles, and the command for each stage:

```
CYCLE ONE  grill -> plan -> task -> subtask -> build -> manifest -> record
           ...once per part of the change. Then, once: commit
CYCLE TWO  brief -> read -> findings -> close        (a new session, after the commit)
```

```sh
# 1. grill — say "grill me on this, then plan it". No cap on questions or
#    rounds; it ends when you and the agent share the same understanding.
# 2. plan
leo plan "rate limiting"           # then fill in goal, non-goals, tasks, budget

# 3. task — one file per plan row, carrying that task's grill
leo task T1
leo task                           # every task, its to-do, its status

# 4. subtask — when a task turns out to hold more than one decision
leo task T1 --sub "in-memory store"   # a heading inside T1.md, not a new file

# 5. build — the agent writes the code, one task at a time

# 6. manifest
leo scan                           # diff -> one row per hunk
leo check                          # rules, hunks, grill, tools, TDD, budget, tests
leo check --verbose                # ...showing every stage
leo use --list                     # which tools built these hunks

# 7. record — the agent may run this. It writes no history.
leo record "api: cap each key at 60 requests per minute"
leo commit --list                  # the cycles recorded and not yet in git

#    Then go back to 1 for the next part. Nothing is in git until:

# 8. commit — yours, never the agent's. One commit, every record in it.
leo commit                         # or: leo commit "api: per-key rate limiting"
```

Then cycle two, which `leo commit` asks for:

```sh
# 9. brief — a new session, and a review of the commit that just landed
leo session --mode review
leo review                         # or: leo review <sha>, leo review main..HEAD

# 10. read — the diff against .leo/review/STANDARDS.md, briefed with what
#    cycle one recorded: goal, manifest, non-goals, and what the grill settled

# 11. findings — one row each: severity, where, what breaks, status

# 12. close — yours, like the commit
leo review --close
```

Then **start a fresh session for the next task.** The record is the stopping
point, not the commit — an agent re-reads its whole context every turn, so a
session's cost grows with the square of its length, and holding one session
open across every cycle of a change is the worst shape available.
`.leo/tasks/` and `.leo/commits/` exist so stopping costs you nothing.

Four things block in cycle one: a hunk with no task, a task with no grill, a
tool switch and the ledger disagreeing, and — while TDD is on — code that
arrived without a test ever being watched to fail. One blocks in cycle two: a
`blocker` finding nobody has fixed or waived. Everything else is a working
note.

## Vendoring it into your repo

Rather than symlinking one clone into every project, build a single
self-contained file and commit it:

```sh
git clone https://github.com/pranesh27-leo/Leo-workflow.git ~/leo
cd ~/leo && ./leo build              # -> dist/leo, one file, no siblings
cp dist/leo ~/work/myrepo/.leo/bin/leo
cd ~/work/myrepo && git add -f .leo/bin/leo
```

Everyone who clones your repo now runs the same leo, pinned to the revision
its header names. It is still bash and still carries every comment, so it can
be reviewed like anything else you commit.

## Requirements

git, bash 3.2, and a POSIX userland. No jq, no node, no network.

## Licence

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Pranesh Kumar.
