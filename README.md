# leo

A workflow for working with coding agents, in ~500 lines of POSIX shell.

It exists to answer one question: **when 500 lines arrive that you did not
type, how do you know they are the right 500 lines — and how do you debug them
at 3am without an AI?**

## The four ideas

1. **The agent grills you before it plans.** It asks questions in rounds — each
   with a recommended default — and stops after each round instead of running
   ahead. Out of that comes `.leo/plan.md`: the goal, the non-goals, numbered
   tasks `T1`, `T2`, …, and a LOC estimate. You build the plan together, and it
   is specific enough to measure against. A vague plan justifies anything.
2. **A manifest makes a diff reviewable.** `leo scan` turns the diff into one
   row per hunk. The agent fills in *which task this serves*, *why*, and *what
   breaks if it is deleted*. You read ~20 rows and spot-check the risky ones.
   `leo check` then rejects any task ID the plan never declared, so the agent
   cannot invent a justification, and reports the unwanted work in lines:
   `2 hunk(s), 47 lines, serve no task`. That is your answer to "which of these
   500 lines did I not ask for?"
3. **The record belongs in the commit message.** Not in git notes, not in a
   side file, not in a chat log. `git blame` → `git show` and you get the reason
   a line exists, from git alone, forever.
4. **A lesson becomes a shell command.** Each `.leo/rules/*.md` holds a check
   that exits non-zero when a known mistake reappears. It runs on every
   `leo check`, costs no tokens, and outlives the session that learned it.

## Install

```sh
ln -s "$PWD/bin/leo" /usr/local/bin/leo
cd ~/your-repo && leo init
```

## Use

```sh
leo plan "rate limiting"        # write down what the change may be
                                # ...then let the agent build it
leo scan                        # split the diff into hunks
                                # ...agent fills in Task / Why / If deleted
leo check                       # rules, unmapped hunks, budget, tests
leo commit "api: rate limit"    # manifest lands in the commit message
```

## Layout

```
bin/leo            dispatch: a command is a file in core/cmd/, no registry
core/lib.sh        every shared helper, one screen
core/cmd/*.sh      one file per command, readable top to bottom
templates/         what `leo init` copies into a repository
```

## Extending it

There are exactly two extension points, and neither requires touching the code:

- **A new check** is a new file in `.leo/rules/`.
- **A new command** is a new file in `core/cmd/`. `leo <name>` finds it.

If a change needs more machinery than that, it probably does not belong here.
Every abstraction in this tool has to earn itself against a simple rule: you
must be able to read the whole thing in one sitting.

## Requirements

git, bash 3.2, and a POSIX userland. No jq, no node, no network.
