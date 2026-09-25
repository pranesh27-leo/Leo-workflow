# Working agreement

## This session

**The developer fills this in. Never edit it yourself — ask.**

    Mode: coding        <- coding | debugging | learning | review | exploration
    TDD:  yes           <- yes | no

`Mode` picks which skills apply, below. `TDD` picks which build stages you
follow in `.agents/leo.md`. If either line is missing or blank, ask for it
before you touch anything — do not assume a default.

## Before anything

1. Read the block above. **Name the mode and the stage in your first line.
   Every reply.**
2. Read `.agents/leo.md` for the stage you are in. Do that stage. Stop there.

Cannot read these files? Say so and stop. Never guess the stage.

## The loop

Cycle one — build it. Every stage in order, one task at a time. Cycle two
reads a commit in a **new session** and cannot edit code.

    1  grill -> plan -> task -> subtask -> build -> manifest -> commit
    2  brief -> read -> findings -> close

**What each stage means, and exactly what to write: `.agents/leo.md`.**
Nothing else describes the loop, so nothing else can disagree with it.

## Skills by mode

| mode | grill | ponytail | caveman | code graph | rtk |
|---|---|---|---|---|---|
| **coding** | every task + subtask | ON | ON | ON | ON |
| **debugging** | every task + subtask | OFF | OFF | ON | ON |
| **learning** | before you build | OFF | OFF | ON | ON |
| **review** | not used | OFF | ON | ON | ON |
| **exploration** | before you build | OFF | OFF | ON | ON |

ON means follow it. OFF means do not — that is the developer's decision, not
a default to work around.

Caveman is OFF in debugging and learning on purpose: it compresses your own
prose, and in those modes the line that looks like noise is routinely the
line that matters.

    .agents/skills/grilling/SKILL.md    how to grill — follow it exactly
    .agents/skills/grill-me/SKILL.md    the trigger
    .agents/skills/ponytail/SKILL.md    do not write code that should not exist
    .agents/skills/caveman/SKILL.md     say it once, say it short
    .agents/tools/graph.md              code graph — call chains, blast radius
    .agents/tools/rtk.md                terminal output reduction

The tools are optional and external. Missing one is not an error: say so and
carry on without it. **Never install anything** — show the developer the
command from the tool's file and let them decide.

## Standing orders

- **Never commit.** Prepare the message, show it, stop. Committing is theirs.
- **Never install.** Name the tool and the command; they run it.
- **Never invent a task ID** to justify a hunk. An honest `-` is the point.
- **Never skip a stage quietly.** Name the one you skipped, then wait.
- The mode and the TDD line are the developer's. Honour them; never change
  them.

After a commit, tell them to start a **fresh session**.
