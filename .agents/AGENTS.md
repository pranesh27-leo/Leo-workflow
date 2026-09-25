# Working agreement

## This session

**The developer fills this in. Never edit it yourself — ask.**

    Mode: coding        <- coding | debugging | learning | review | exploration
    TDD:  yes           <- yes | no

If either line is blank, ask for it before you touch anything. Do not assume
a default.

## Before anything

1. Read the block above. **Name the mode and the stage in your first line.
   Every reply.**
2. Open `.agents/leo.md`, find your stage, do that stage, stop there.

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

## Skills

| skill | file | what it governs |
|---|---|---|
| grill-me | `.agents/skills/grill-me/SKILL.md` | interview before building |
| tdd | `.agents/skills/tdd/SKILL.md` | test first, and watch it fail |
| ponytail | `.agents/skills/ponytail/SKILL.md` | what you build — the laziest thing that works |
| caveman | `.agents/skills/caveman/SKILL.md` | what you say — cut what was not asked for |
| humanizer | `.agents/skills/humanizer/SKILL.md` | how prose reads — remove AI tells |

| mode | grill | tdd | ponytail | caveman | humanizer | graph | rtk |
|---|---|---|---|---|---|---|---|
| **coding** | every task + subtask | per `TDD:` | ON | ON | on demand | ON | ON |
| **debugging** | every task + subtask | per `TDD:` | OFF | OFF | on demand | ON | ON |
| **learning** | before you build | OFF | OFF | OFF | **ON** | ON | ON |
| **review** | not used | OFF | OFF | ON | **ON** | ON | ON |
| **exploration** | before you build | OFF | OFF | OFF | on demand | ON | ON |

ON means follow it. OFF means do not — that is the developer's decision, not
a default to work around. **on demand** means open it when you are writing
prose worth editing, not on every reply: it is 28 KB and most replies are not
prose.

Caveman is OFF in debugging and learning on purpose — it cuts, and in those
modes the line that looks like noise is routinely the line that mattered.
Ponytail is ON only in coding, because it governs code you are writing.

## Tools

| tool | file | what it does |
|---|---|---|
| code graph | `.agents/tools/graph.md` | who calls what, what a diff touches |
| rtk | `.agents/tools/rtk.md` | filters shell output structurally |

Both optional and external. Missing one is not an error: say so and carry on.
**Never install anything** — show the developer the command from the tool's
file and let them decide.

## Standing orders

| never | instead |
|---|---|
| commit | prepare the message, show it, stop |
| install | name the tool and the command; they run it |
| invent a task ID | write `-` in the manifest and say it served no task |
| skip a stage quietly | name the stage you skipped, then wait |
| change `Mode:` or `TDD:` | ask them to |

After a commit, tell them to start a **fresh session**.
