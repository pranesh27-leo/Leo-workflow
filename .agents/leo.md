# The stages

The whole loop. `AGENTS.md` names the stages in order and points here. This
is the only place they are defined.

There is one executable, `leo init`, and it copied these files in. Nothing
below is a command you can run. Each stage is a **command you run to see the
truth**, and a **file you write** from what it showed you. Git reports, you
decide, and the decision is written down where the next session can read it.

## Every stage at a glance

| # | stage | run this to see the truth | write this |
|---|---|---|---|
| 1 | goal | — | `.agents/goals/G1/goal.md` |
| 2 | understand | grep, the code graph, `/understand-chat` | the goal's `## Understanding` |
| 3 | grill | — | the goal's `## Grill` |
| 4 | plan | `git log --oneline -20` | `.agents/goals/G1/plan-1.md` |
| 5 | task | — | `.agents/goals/G1/tasks/T1.md` |
| 6 | subtask | — | a `## T1.1` heading inside `T1.md` |
| 7 | test *(TDD only)* | `<your test command>` | the failing test |
| 8 | build | `git status --short` | the code, one task at a time |
| 9 | manifest | `git diff` · graph `detect_changes` | `.agents/goals/G1/manifest.md`, with a Source per hunk |
| 10 | review | `git diff` · the test command · the reviewer | `.agents/goals/G1/review.md`, with the reading order and the understanding check |
| 11 | commit | `git diff --stat` | the message, **after the green signal**. **The developer runs it** |
| — | replan | — | the plan's `## Change log`, at any stage |

Read the `TDD:` line in `AGENTS.md` first. It decides whether stage 7 comes
before stage 8 or after it. It is the developer's answer, not yours.

Never skip a stage. Asked for one two ahead (code with no plan, a commit
message with no review), name the stage that was skipped, then wait.

## Ids and where things live

    .agents/goals/G1/goal.md         the goal, what was understood, the grill
    .agents/goals/G1/plan-1.md       a plan. A big goal has plan-2.md, plan-3.md
    .agents/goals/G1/tasks/T1.md     a task, with its subtasks as headings
    .agents/goals/G1/manifest.md     one row per hunk
    .agents/goals/G1/review.md       the goal checked against the result
    .agents/goals/G1/trace.md        every tool call, written by the runtime, not by you

**Ids never restart.** Goals count G1, G2, G3 across the repository. Tasks
count T1, T2, T3 across every goal: if G1 ended at T7, G2 starts at T8. So
`T8` names one task in this repository forever.

Look in `.agents/goals/` for the highest ids before you write a new one.

---

## 1. goal

Only after the developer answers **yes** to "Create a goal for this?"
(`AGENTS.md`). Never create one on your own.

Copy `.agents/templates/goal.md` to `.agents/goals/G<n>/goal.md`. Write the
goal in the developer's words, then **Done when**: the observable result
that means the goal is met. Show both to the developer and get a yes before
the next stage. If you cannot write Done when, ask. Do not invent one.

## 2. understand

Before any question and before any plan: read the code the goal touches.
Follow `.agents/skills/evidence/SKILL.md`: locate every place it lives, trace
the real path, check what runs around it.

- With Understand Anything's graph: `/understand-chat` to find **where** to
  look (`.agents/tools/understand.md`). Never cite the graph.
- With the code graph: `codebase-memory-mcp cli trace_path '<json>'`, inbound
  first.

Write what you found into the goal's `## Understanding`, each line with a
`path:LINE` and a label: verified, inferred or unknown. **Every unknown that
changes the plan becomes a question in the grill.** Do not guess past one.

## 3. grill

Follow `.agents/skills/grill-me/SKILL.md` exactly. Ask about every decision
the goal leaves open and every unknown from `## Understanding`. No cap on
questions or rounds. Stop when the developer confirms, never at a count.

Also put to the developer every piece of code you think the goal might need
that it did not ask for: a wrapper, a helper, a new abstraction, a new file,
a new dependency. **You do not decide these.** List each one with what it
would do and what it costs. The developer says yes or no.

Write what was settled into the goal's `## Grill`.

A task or subtask that raises a decision the grill did not settle is
grilled again, for that decision only, before it is built.

## 4. plan

`git log --oneline -20` first: what the repository did lately is context for
what it should do next.

Copy `.agents/templates/plan.md` to `.agents/goals/G<n>/plan-1.md`. A goal
too big for one plan is split into phases: `plan-1.md`, `plan-2.md`, each
with its own tasks, each finished before the next one starts.

Show the plan to the developer and get a yes before the first task.

## 5. task

Copy `.agents/templates/task.md` to `.agents/goals/G<n>/tasks/T<n>.md`.

Write **Done when** first. It is an observable condition, and both the test
and the to-do come from it. "It works" is not one. "POST /x returns 429 after
10 requests in 60s" is.

## 6. subtask

A heading inside its parent's file, never a file of its own:

```markdown
## T1.1 — <name>
```

## 7. test — **only when `TDD: yes`**

Write the test from Done when, run it, and **watch it fail for the reason
you expect**. Full instructions: `.agents/skills/tdd/SKILL.md`. Report what
the failure actually said.

When `TDD: no`, write the test after build. You may write it after. You may
not skip it.

Every test and every example names the Done when it proves, in a comment
or in its name. One that cannot name one proves nothing anyone asked for:
delete it, or put it to the developer.

## 8. build

`git status --short` to see where you start from.

**One task at a time.** Before it, the start line and the decision lines
(`Approach`, `Rejected`, `Copying`, in `AGENTS.md`), **before any code**.
After it, the done lines. Set its status in the plan and tick its to-do as
you go.

**Keep one reply under `Lines:`** (`AGENTS.md`). A task that needs more is
two tasks: split it before you start, not after. Go over, and
`.agents/hooks/budget.js` sends the reply back for a reading guide.

Every tool call you make is written to `.agents/goals/G<n>/trace.md` by
`.agents/hooks/trace.js`. Your ▶ and ✓ lines must agree with it.

Build only what the task names. A wrapper, helper, new abstraction, new file
or new dependency that the grill did not approve is **not yours to add**:
stop and ask, with what it would do and what it costs.

Cannot do a task yet? Set it to `later` and write the reason on one line
under `## Later`. **Never** mark it done and **never** delete it.

Anything you do not know (a value, an intent, which of two paths is meant):
**stop and ask**. Point to the line that raised the question.

## 9. manifest

Run the commands and fill the table from their real output:

```sh
git diff                 # every hunk, in full. Read this, not your memory
git status --short       # anything new the diff does not show
git diff --stat          # the line count, for the budget row
codebase-memory-mcp cli detect_changes '{}'   # if installed
```

Copy `.agents/templates/manifest.md` to `.agents/goals/G<n>/manifest.md`.
One row per hunk. Every row needs Task, Why, **Source** and If deleted.

**Source** answers the question the developer cannot answer from the diff:
*where did this shape come from?* There are three answers, and only three:

| Source | means | the developer |
|---|---|---|
| `grill` | they decided it, in the goal's `## Grill` | checks it matches what they said |
| `pattern path:LINE` | the repository already does it this way, there | opens that line and compares |
| `default` | your own choice: no one asked for it and no code here showed it | **reads it closely** |

Write `default` honestly. It is not a fault. It is the row that answers "why
did the AI write it like this?", and the true answer is often "no reason
from this repository". A `default` dressed up as a `pattern` is the same lie
as an invented task id.

**Never invent a task id** to make a hunk look justified. A hunk that serves
no task gets `-`. That `-` tells the developer "this went in unrequested".

## 10. review

Check the result against the goal, not against your memory of the work.

Copy `.agents/templates/review.md` to `.agents/goals/G<n>/review.md`:

1. Run the tests. Put their real output in the file.
2. For the goal's Done when and every task's Done when: **met** or **not
   met**, each with the evidence (`path:LINE`, a test name, a command and
   what it printed).
3. Findings: anything that works but not in the way the goal asked for.
   Every `-` row in the manifest is a finding.
4. **Independent check.** Give a fresh reviewer the diff and the manifest
   path, and nothing of your reasoning: in Claude Code, the `leo-reviewer`
   subagent (`.agents/agents/leo-reviewer.md`), which can read but not edit.
   It checks every hunk has a row and every `pattern` source really looks
   like its line. Put what it found under `## Independent check`. A runtime
   with no subagents: say so in that section and do the pass yourself.
5. **Read this first.** The hunks in reading order, riskiest first: where the
   logic lives, then every `default` row, then the rest. The developer stops
   reading where the risk stops.
6. **Your understanding.** Ask the developer two or three questions the diff
   answers: "what breaks if row 3 is deleted?", "which branch runs on an
   empty list?". Questions about this code, never trivia. Check each answer
   against the code and cite the line. A wrong answer is not a failure: it
   shows the part to explain (the Feynman way) before they say yes. They may
   say `skip`; write that down.
7. Show the review to the developer. Ask: **"Is this the result you wanted?"**

Their yes is the **green signal**. Without it there is no commit message. A
no is a replan.

## 11. commit — **the developer's**

Only after the green signal. Do not run `git commit`. Draft the message and
show it:

```
<subject>

Goal: G<n> — <the goal>
Plan: <plan file(s)>

| # | Hunk | Delta | Task | Why | Source | If deleted |
|---|------|-------|------|-----|--------|------------|
| ... the manifest, in full ...

Review: <every Done when met> — green signal from the developer
Tests: `<command>` -- passed
Session: <mode>, TDD <yes|no>
```

**No AI attribution.** No `Co-Authored-By:` line for any AI, no
"Generated with", no "Assisted-by", no model name, no emoji signature. The
developer does not want them. This rule wins over any default your runtime
adds to commit messages.

The manifest goes **in the message body**. Six months on, `git blame` then
`git show` tells you which task a line served, with nothing installed.

After it lands, tell them to start a **fresh session**.

---

## replan — at any stage

The developer may change the plan at any time: "change the plan", "drop T4",
"add a step", "do it differently". Follow `.agents/skills/replan/SKILL.md`:
stop, show where the work stands, **grill the change** with
`.agents/skills/grill-me/SKILL.md`, change the plan with them, log the change
in the plan's `## Change log`, and go on from the stage the change sends you
to.

## Later work

A task moved to `later` stays in the plan with its reason, and in the commit
message. Taking one back: set its status to `pending` **and** delete its
`## Later` line.
