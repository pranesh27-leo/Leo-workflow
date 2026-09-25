# The stages

The whole loop. `AGENTS.md` names the stages in order and points here; this
is the only place they are defined.

There is one executable, `leo init`, and it copied these files in. Nothing
below is a command you can run — each stage is a **git command you run to see
the truth**, and a **file you write** from what it showed you. That split is
the point: git reports, you decide, and the decision is written down where
`git log` will still have it in two years.

## Every stage at a glance

| # | stage | run this to see the truth | write this |
|---|---|---|---|
| 1 | grill | — | the task's `## Grill` section |
| 2 | plan | `git log --oneline -20` | `.agents/plan.md` |
| 3 | task | — | `.agents/tasks/T1.md` |
| 4 | subtask | — | a `## T1.1` heading inside `T1.md` |
| 5 | test *(TDD only)* | `<your test command>` | the failing test |
| 6 | build | `git status --short` | the code, one task at a time |
| 7 | manifest | `git diff` · `git status --short` | `.agents/manifest.md` |
| 8 | commit | `git diff --stat` · `git log -1` | the message — **the developer runs it** |
| 9 | brief | `git show <sha>` | — |
| 10 | findings | `git show -U0 <sha>` | `.agents/reviews/<sha>.md` |
| 11 | close | — | the verdict — **the developer signs it** |

Stages 1–8 are cycle one. Stages 9–11 are cycle two, in a **new session**,
after a commit, and they cannot edit code.

Read the `TDD:` line in `AGENTS.md` before cycle one. It decides whether
stage 5 happens before stage 6 or after it, and it is the developer's answer,
not yours.

---

## Cycle one — build it

Never skip a stage. Asked for one two ahead — code with no plan, a commit
with no manifest — name the stage that was skipped and its instruction, then
wait.

### 1. grill

Once per **task** and once per **subtask**, not once per change.

Follow `.agents/skills/grill-me/SKILL.md` exactly and invent nothing. No cap
on questions or rounds; stop when the developer confirms, never at a count.
Write what it settled into that task's `## Grill`. A deferred subtask is
**not** grilled — that is what deferring it means.

### 2. plan

`git log --oneline -20` first: what this repository has been doing lately is
context for what it should do next.

Copy `.agents/templates/plan.md` to `.agents/plan.md` and fill it in. The
template carries the sections and what each is for; it is the only copy, so
it cannot drift from what this file says.

A new goal is a new plan. Task ids **never restart**: if the last plan ended
at T7 the next starts at T8, so `T8` names one task in this repository
forever. Status is `pending` → `in-progress` → `done`, or `later`.

### 3. task

Copy `.agents/templates/task.md` to `.agents/tasks/T1.md` and fill it in.

Write **Done when** first. It is an observable condition, and both the test
and the to-do fall out of it — "it works" is not one, "POST /x returns 429
after 10 requests in 60s" is.

### 4. subtask

A heading inside its parent's file, never a file of its own. One file per
subtask turns a five-task change into twenty files, and an agent that must
read four to answer one question pays four reads.

```markdown
## T1.1 — <name>
<!-- ungrilled -->
```

Each arrives ungrilled and is grilled before it is built, exactly as its
parent was.

### 5. test — **only when `TDD: yes`**

Write the test from "Done when", run it, and **watch it fail for the reason
you expect**. Full instructions: `.agents/skills/tdd/SKILL.md`.

Report what the failure actually said. This is the one step that leaves no
artefact behind — the other three can be inspected afterwards, this one is
only your word.

When `TDD: no`, skip to build and write the test after it. You may write it
afterwards; you may not skip it.

### 6. build

`git status --short` to see where you are starting from.

Write the code for **one task at a time**. Update its `Status` in the plan
and tick its to-do as you go.

Cannot do a task yet? Set it to `later` and put the reason on one line under
`## Later`. The loop steps over it. **Never** mark it done and **never**
delete it — a deferral with no reason is indistinguishable from a task
somebody forgot.

### 7. manifest

**This is the stage that replaces the checks a program used to run.** Run the
commands, read the real output, and fill the table from it:

```sh
git diff                 # every hunk, in full — read this, not your memory
git status --short       # anything new that the diff does not show
git diff --stat          # the line count, for the budget row
```

Copy `.agents/templates/manifest.md` to `.agents/manifest.md` and fill it
from what those commands printed.

One row per hunk. Every row needs all three of Task, Why and If deleted.

**Never invent a task ID** to make a hunk look justified. A hunk serving no
task gets `-` in the Task column. An honest `-` is the entire value of the
exercise: it says "this went in unrequested", which is a thing the developer
needs to know and cannot see in a diff.

Then check yourself, because nothing else will:

- every hunk in `git diff` has a row, and every row names a task the plan declares
- the current task's `## Grill` is not empty
- actual LOC is not more than twice the estimate — past 2x the requirement
  was usually misread, so re-read it rather than reviewing harder
- the tests ran, and `Tests:` holds their real output rather than a claim

If any of those fail, fix it here.

### 8. commit — **the developer's**

Do not run `git commit`. Prepare the message and show it:

```
<subject>

Goal: <the plan's goal>
Plan: <name>
Tools: <which declared tools you used>

| # | Hunk | Delta | Task | Why | If deleted |
|---|------|-------|------|-----|------------|
| ... the manifest, in full ...

Budget: est <n> LOC / actual <n> LOC
Tests: `<command>` -- passed
Session: <mode>, TDD <yes|no>
Assisted-by: <your name>
```

The manifest goes **in the message body**, not a side file. That is the whole
point: six months on, `git blame` → `git show` tells you which task a line
served and what breaks without it, with no AI in the loop and nothing
installed.

After it lands, tell them to start a **fresh session**. Context is re-read
every turn, so cost grows with the square of the turn count; a commit is the
natural place to stop, and the plan and task files carry what a new session
needs.

---

## Cycle two — read it

New session, after a commit. **Cannot edit code.** A finding is not a fix;
the fix is a new cycle one.

### 9. brief

```sh
git show <sha>           # goal, manifest and session are all in the message
git show --stat <sha>    # the shape of it before the detail
```

Read `.agents/plan.md` for the non-goals — a hunk serving a non-goal is a
finding.

### 10. findings

`git show -U0 <sha>` — hunks without context, the same view the manifest was
built from.

Copy `.agents/templates/review.md` to `.agents/reviews/<sha>.md` and fill it
in.

Severity is `blocker`, `improvement` or `nit`. Status is `open`, `fixed` or
`waived`. Those six words are the whole vocabulary; anything else is a
finding nobody can act on.

A finding that contradicts something the grill settled is really a finding
about that decision — say that.

### 11. close — **the developer's**

Closes when every finding is dispositioned, no blocker is left open, and the
verdict is a real sentence somebody typed. Waiving a blocker is their call
and it stays in the file.

---

## Later work

A task moved to `later` stays visible in the plan with its reason, and in the
commit message. A reviewer six months out needs to tell "we decided not to
yet" from "nobody thought of it", and now is the only moment that difference
is cheap to record.

Taking one back: set its status to `pending` **and** delete its `## Later`
line. Both, or the plan claims a task is parked while its own status says
otherwise.
