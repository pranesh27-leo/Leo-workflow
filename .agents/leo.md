# The stages

Every stage, what it means, and exactly what to do. This is the only
description of the loop — `AGENTS.md` names the stages in order and points
here for each one.

There is no program. Nothing below is a command you can run; each stage is
something you do and something you write down. That is deliberate: a harness
that needs installing is a harness that does not work on somebody's machine.

Read the `TDD:` line in `AGENTS.md` before you start cycle one. It selects
which version of the build stages you follow, and it is the developer's
answer, not yours.

---

## Cycle one — build it

Stages in order. Never skip one. Asked for a stage two ahead — code with no
plan, a commit with no manifest — name the stage that was skipped and its
instruction, then wait.

### 1. grill

Interview the developer until the decisions are settled. Once per **task**
and once per **subtask**, not once per change.

Follow `.agents/skills/grilling/SKILL.md` exactly and invent nothing. No cap
on questions or rounds; stop when the developer confirms, never at a count.

Write what it settled into the task's `## Grill` section. A task with an
empty grill is a task built on whatever you assumed.

A deferred subtask is **not** grilled — that is what deferring it means.

### 2. plan

Write `.agents/plan.md`:

```markdown
# Plan: <name>

## Goal
<One sentence: what changes, and why.>

## Non-goals
<What this change does not touch. This is what stops scope creep.>

## Wrong-change signal
<The one observation that would mean this is the wrong change entirely.>

## Tasks

| #  | Task   | Files   | Est LOC | Status  |
|----|--------|---------|---------|---------|
| T1 | <task> | <files> | <n>     | pending |
| T2 | <task> | <files> | <n>     | pending |

## Later
<!-- One line per deferred task, with its reason. -->

## Budget
est: <n> LOC
```

A new goal is a new plan. Task ids **never restart**: if the last plan ended
at T7, the next one starts at T8, so `T8` names one task in this repository
forever. Status is `pending` → `in-progress` → `done`, or `later`.

### 3. task

Give the task a file, `.agents/tasks/T1.md`:

```markdown
# T1 — <name>

Files: <files>
Est:   <n> LOC

## Done when
<The observable condition. Write this first; the to-do falls out of it.>

## Grill
<!-- What the grill settled. Empty means it was never grilled. -->

## To-do
- [ ] <step>
```

### 4. subtask

A subtask is a **heading inside its parent's file**, never a file of its own.
One file per subtask turns a five-task change into twenty files, and an agent
that must read four of them to answer one question pays four reads.

```markdown
## T1.1 — <name>
<!-- ungrilled -->
```

Each subtask arrives ungrilled and is grilled before it is built, exactly as
its parent was.

### 5. build

Write the code for **one task at a time**. Update its `Status` in the plan as
you go, and tick its to-do.

**If `TDD: yes`** — this stage is four steps and the order is the point:

1. Write the test from "Done when". The spec, not the implementation.
2. Run it. **Watch it fail**, and confirm it failed for the reason you
   expect. A test that passes before the code exists is testing nothing.
3. Implement the smallest thing that makes it pass.
4. Run it. Watch it pass.

Report which of the four you did. If you skipped step 2, say so in your first
line — do not let it pass silently.

**If `TDD: no`** — write the code, then write the test. You may write the
test afterwards; you may not skip it.

Cannot do a task yet? Move it to `later` in the plan with the reason, on one
line under `## Later`. The loop steps over it. **Never** mark it done and
**never** delete it — a deferral without a reason is indistinguishable from a
task somebody forgot.

### 6. manifest

Turn the diff into a table. `git diff` and read it — not your memory of what
you wrote. Write `.agents/manifest.md`:

```markdown
# Manifest

| # | Hunk | Delta | Task | Why | If deleted |
|---|------|-------|------|-----|------------|
| 1 | `src/api.js:42` | +12/-3 | T1 | rate limit needs a window | requests are unbounded |

Budget: est <n> LOC / actual <n> LOC
Tests: `<command>` -- <paste the real output>
```

One row per hunk. Every row needs all three of Task, Why and If deleted.

**Never invent a task ID** to make a hunk look justified. A hunk that serves
no task gets `-` in the Task column — an honest `-` is the entire value of
the exercise, and it says "this went in unrequested", which is a thing the
developer needs to know.

Check yourself before you go on:

- every hunk has a row, and every row has a task id the plan declares
- the current task is grilled
- actual LOC is not more than twice the estimate — past 2x the requirement
  was usually misread, so re-read it rather than reviewing harder
- the tests ran, and `Tests:` holds their real output, not a claim

If any of those fail, fix them here. This is the stage that replaces the
check that used to be a program, and it only works if you are honest at it.

### 7. commit

**This stage is the developer's.** Do not run `git commit`.

Prepare the message and show it to them:

```
<subject>

Goal: <the plan's goal>
Plan: <name>
Tools: <which of the declared tools you used>

| # | Hunk | Delta | Task | Why | If deleted |
|---|------|-------|------|-----|------------|
| ... the manifest, in full ...

Budget: est <n> LOC / actual <n> LOC
Tests: `<command>` -- passed
Session: <mode>, TDD <yes|no>
Assisted-by: <your name>
```

The manifest goes **in the message body**, not in a side file. That is the
whole point of it: six months from now `git blame` → `git show` tells you
which task a line served and what breaks without it, with no AI in the loop
and no tooling to install.

After it lands, tell them to start a **fresh session**. A session re-reads
its whole context every turn, so cost grows with the square of the turn
count; a commit is the natural place to stop, and the plan and task files
carry everything a new session needs.

---

## Cycle two — read it

After a commit, in a **new session**. Cycle two **cannot edit the code**. A
finding is not a fix; the fix is a new cycle one.

### 8. brief

Read the commit: `git show <sha>`. The goal, the manifest and the session are
all in the message, because cycle one put them there. Read
`.agents/plan.md` for the non-goals — a hunk that serves a non-goal is a
finding.

### 9. findings

Write `.agents/reviews/<sha>.md`:

```markdown
# Review: <sha> — <subject>

| # | Severity | Finding | Where | Status |
|---|----------|---------|-------|--------|
| 1 | blocker  | <what>  | `f:42`| open   |

Verdict: <ship | fix-first> — <why>
```

Severity is `blocker`, `improvement` or `nit`. Status is `open`, `fixed` or
`waived`. Those six words are the whole vocabulary; anything else is a
finding nobody can act on.

Read the diff against the repository's own standards, not against your
taste. A finding that contradicts something the grill settled is really a
finding about that decision — say that.

### 10. close

**This stage is the developer's.** A review closes when every finding is
dispositioned, no blocker is left open, and the verdict is a real sentence
somebody typed. Waiving a blocker is their call and it stays in the file.

---

## Later work

A task moved to `later` stays visible in the plan, with its reason, and in
the commit message. A reviewer six months out needs to tell "we decided not
to yet" from "nobody thought of it", and now is the only moment that
difference is cheap to record.

Taking one back: set its status to `pending` and delete its `## Later` line.
Both, or the plan claims a task is parked while its own status says
otherwise.
