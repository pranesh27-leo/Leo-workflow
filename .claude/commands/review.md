---
description: Open cycle two — a leo review of a commit that has already landed.
allowed-tools: Bash, Read, Grep, Glob, Edit, Task
---

You are running **cycle two** of the leo workflow: a code review of a change
that is already committed.

Read `.leo/workflow.md` stage 6 before you do anything else. What follows is
the shape of the work, not a replacement for it.

## The one rule

**You cannot edit the code under review.** There is no stage in this cycle that
writes to the source tree. If you want to change a line, you have found a
finding — write it down. The fix is a new cycle one, and starting it is the
developer's call, not yours.

The only file you may write is the review itself, under `.leo/reviews/`.

## 1. Open it

```
!`leo review $ARGUMENTS`
```

With no argument that reviews `HEAD`. It writes `.leo/reviews/<sha>.md`, already
briefed with what cycle one recorded.

If the command says a review is already open, read it and continue from
whatever is unfinished — do not re-open it, and do not pass `--force`, which
would discard someone's work.

## 2. Read, in this order

1. **The "What was asked for" section of the review file.** The goal, the
   manifest, the non-goals and what the grill settled. Read it *first*. A
   reviewer who does not know what was asked for can only check the code
   against itself, which is how a change that is internally consistent and
   completely wrong passes. If this section is thin, the dev cycle was thin,
   and that is your first finding.
2. **`.leo/review/STANDARDS.md`.** The rubric, and the only thing a finding here
   has to clear. Read the copy in *this* repository — teams amend it.
3. **The diff.** `git show <sha>`, or `git diff <range>`. All of it.

The **Signals** section is a grep, not an opinion. It says where to look and
never what to think. Most signals are nothing; clearing one costs a glance. A
signal it did *not* raise is the failure mode, so never treat that list as the
scope of your review.

## 3. Delegate the reading if it is large

For anything past a few hundred lines, hand the analysis to the
`code-review` subagent — it keeps the diff out of this thread and returns
findings. Give it the diff, the standards, and the "What was asked for" section.
You stay responsible for what lands in the file.

## 4. Write the findings

Edit the review file. One row per finding:

| Column | What goes in it |
|---|---|
| Severity | `blocker`, `improvement` or `nit` — nothing else parses |
| Where | `file:line`, not "in the auth code" |
| Finding | what is wrong, stated so it can be disagreed with |
| Why it matters | the failure it causes, or the principle it breaks |
| Status | `open` for anything you are filing |

Then the **Verdict** line (`ship` or `fix-first`, and one line of why) and the
**Read first** section: the 2-3 places a human should look before anything
else — widest blast radius, anything security-relevant, and any judgement call
the developer has not seen. Name them even where you found nothing wrong.

Hold yourself to the standards' own bar:

- Every finding names a failure. If you cannot say what breaks, it is a nit or
  it is nothing. "I would have written it differently" is not a finding.
- Do not re-litigate scope. The manifest already answered whether each hunk was
  asked for, and it is quoted in the file for you.
- Do not inflate and do not deflate. A reviewer who files improvements as
  blockers is ignored on the one that mattered; one who files a real security
  defect as a nit to avoid an argument has wasted the exercise.
- Zero findings is a claim. If you found nothing, the verdict says what you
  actually read to conclude that.
- Anything a linter could catch is not a finding — it is a missing rule. Say so,
  and offer `.leo/rules/<NAME>.md`.

## 5. Stop

Run `leo review --close`. Expect it to refuse while blockers are open — that is
the gate working, not a problem to route around.

**Do not fix the blockers, and do not waive them.** Report what you found, say
which you would recommend for each — a fix cycle (`leo plan "fix: <sha> review"`)
or a waiver — and wait. Having found the problem is not the same as being
entitled to decide what it is worth.
