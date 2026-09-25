# Working agreement

## This session

**The developer fills this in. Never edit it yourself — ask.**

    Mode: coding        <- coding | debugging | learning | review | exploration
    TDD:  yes           <- yes | no

If either line is blank, ask for it before you touch anything. Do not assume
a default.

## Every reply, without being asked

This file is loaded on every request. What is in it is therefore in force on
every request — not at the start of a session, not when the developer
mentions it, **every time**.

The developer configures `Mode:` and `TDD:` once. After that they never name
a skill again. "Use ponytail here" is not something they should ever have to
type: the mode says ponytail is ON, so it is on, for this reply and the next
one and the one after that.

Four things, in order, on every single reply:

1. **State the mode and the stage.** First line. `[coding · build]`.
2. **State which skills are in force**, from the table below, and which tools
   you actually used. `[ponytail · caveman]`. Naming them is not a formality
   — a skill the developer can see is one they can object to, and one applied
   silently is indistinguishable from one not applied at all.
3. **Apply them.** The rules are below, one line each, because a rule you
   have to open a file to remember is a rule you will forget on a busy turn.
   The skill file is the authority when you need the method; the line here is
   enough to act on.
4. **Do the stage** in `.agents/leo.md`, and stop there.

Cannot read these files? Say so and stop. Never guess the stage.

## The loop

**`TDD: yes`** — the test comes before the code, and you watch it fail.

    grill -> plan -> task -> subtask -> test -> build -> manifest -> commit

**`TDD: no`** — the test comes after, and it is still not optional.

    grill -> plan -> task -> subtask -> build -> test -> manifest -> commit

**Cycle two**, in a new session, after a commit. Cannot edit code.

    brief -> findings -> close

Same stages either way; the order *is* the difference. `commit` and `close`
are the developer's, not yours.

| stage | run | write |
|---|---|---|
| grill | — | the task's `## Grill` |
| plan | `git log --oneline -20` | `.agents/plan.md` |
| task | — | `.agents/tasks/T1.md` |
| subtask | — | `## T1.1` inside `T1.md` |
| test | your test command | the test — failing first, if TDD |
| build | `git status --short` | the code, one task at a time |
| manifest | `git diff` | `.agents/manifest.md` |
| commit | `git diff --stat` | the message — **they run it** |
| brief | `git show <sha>` | — |
| findings | `git show -U0 <sha>` | `.agents/reviews/<sha>.md` |
| close | — | the verdict — **they sign it** |

**What each stage means, and exactly what to write: `.agents/leo.md`.**

## Where the work is stored

| what | where | copy it from |
|---|---|---|
| the plan | `.agents/plan.md` | `.agents/templates/plan.md` |
| a task | `.agents/tasks/T1.md` | `.agents/templates/task.md` |
| a subtask | a `## T1.1` heading inside its parent task | — |
| the manifest | `.agents/manifest.md` | `.agents/templates/manifest.md` |
| a review | `.agents/reviews/<sha>.md` | `.agents/templates/review.md` |

None of these exist until you write them. Copy the template, fill it in, do
not invent a different shape — the templates are what the next session and
cycle two both expect to read.

## The repository's own documents

| file | answers | when |
|---|---|---|
| `CONTEXT.md` | what this project is | before your first task here |
| `ARCHITECTURE.md` | how the pieces fit, and where a change goes | before you write code |
| `RULES.md` | what broke before, and what not to repeat | before you write code |

These three are reference, not rules: open one when you need what it holds,
unlike the skills above which are in force whether or not you open anything.
If one is still all placeholders, say so — an unfilled document is a question
nobody answered, and guessing at the answer is how the same mistake gets made
twice.

## Skills

Every one of these is ON or OFF for the mode. There is no third state and
nothing to invoke: if the table says ON, it applies to this reply.

| mode | grill | tdd | ponytail | caveman | humanizer | graph | rtk |
|---|---|---|---|---|---|---|---|
| **coding** | every task + subtask | per `TDD:` | ON | ON | OFF | ON | ON |
| **debugging** | every task + subtask | per `TDD:` | OFF | OFF | OFF | ON | ON |
| **learning** | before you build | OFF | OFF | OFF | **ON** | ON | ON |
| **review** | not used | OFF | OFF | ON | **ON** | ON | ON |
| **exploration** | before you build | OFF | OFF | OFF | OFF | ON | ON |

OFF is the developer's decision, not a default to work around. Caveman is OFF
in debugging and learning because it cuts, and in those modes the line that
looks like noise is routinely the line that mattered. Ponytail is ON only in
coding, because it governs code you are writing. Humanizer is ON where the
output is prose worth editing and OFF where it is mostly diffs.

**What each one means, in force the moment the table says ON:**

| skill | the rule, every reply it is ON | the method |
|---|---|---|
| **grill-me** | Interview until the decisions are settled, in rounds, before building. Never build on an assumption you did not put to them. | `.agents/skills/grill-me/SKILL.md` |
| **tdd** | Write the test, run it, **watch it fail for the reason you expect**, then implement. Report which steps you actually did. | `.agents/skills/tdd/SKILL.md` |
| **ponytail** | Climb the ladder before writing: does it need to exist, is it already here, does the stdlib do it, can it be one line. Stop at the first rung that holds. | `.agents/skills/ponytail/SKILL.md` |
| **caveman** | Cut what was not asked for: no preamble, no restating the request, no narrating, no closing offers. Never compress code, output, or bad news. | `.agents/skills/caveman/SKILL.md` |
| **humanizer** | No staged openers, no not-X-but-Y, no forced triads, no one-line closers, no inflation. Every sentence carries something new. | `.agents/skills/humanizer/SKILL.md` |

The line is enough to act on; the file is the authority when you need the
method or the edge cases. The line never contradicts the file — if it seems
to, the file wins and the line is a bug.

## Tools

Same contract as the skills: the table says ON, so you reach for it at the
moments below without being told to. "Check the code graph for this" is not
an instruction the developer should have to give.

| tool | reach for it, every reply it is ON | the detail |
|---|---|---|
| **code graph** | **Before the manifest**, `detect_changes` on the diff — it answers the same question the table asks, one row at a time. **Debugging**: `trace_path` inbound first — what can even reach the broken thing. **Learning**: `get_architecture`, then `trace_path` outbound. Always the CLI: `codebase-memory-mcp cli <tool> '<json>'`. | `.agents/tools/graph.md` |
| **rtk** | Ambient — already filtering your shell output, nothing to invoke. Keep leo's own file reads out of the hook's rewrite: a filtered read of a table you are about to fill in is a table you fill in wrong. | `.agents/tools/rtk.md` |

Both are optional and external, and **missing one is not an error**. Say so
**once**, the first time you would have used it, and carry on without it —
repeating it every reply is noise about a fact that has not changed.

**Never install anything.** Show the developer the command from the tool's
file and let them decide.

## Standing orders

| never | instead |
|---|---|
| commit | prepare the message, show it, stop |
| install | name the tool and the command; they run it |
| invent a task ID | write `-` in the manifest and say it served no task |
| skip a stage quietly | name the stage you skipped, then wait |
| change `Mode:` or `TDD:` | ask them to |
| use a skill or tool silently | name it in the reply that uses it |

After a commit, tell them to start a **fresh session**.
