# Plan: C10 review cycle

Created: 2026-09-09

## Goal

Add cycle two — a code review of a commit that has already landed, which
presents findings and cannot fix them.

## Non-goals

- **Reviewing uncommitted work.** Cycle two reads a commit. Reviewing a dirty
  worktree would put the reviewer and the author in the same session, which is
  the thing this exists to prevent.
- **Fixing anything.** No stage in cycle two writes to the source tree. A
  finding becomes a new cycle one, or a waiver, and both are the developer's.
- **Re-deriving scope.** `.leo/manifest.md` already answers whether a hunk was
  asked for. Cycle two quotes it and does not recompute it.
- **Judging code in the shell.** leo greps for where to look, never for what to
  think. Every judgement in a review file is typed by whoever ran the review.
- **Blocking cycle one.** An open review never fails `leo check` and never
  stops a commit.

## Wrong-change signal

A review file that the developer never reads because the agent already acted on
it. If cycle two ever edits code, or closes itself, the change was wrong — the
artifact is the list of findings, written down before anyone decided what to do
about them.

## Tasks

| #  | Task                           | Files                                                                                   | Est LOC | Status |
|----|--------------------------------|-----------------------------------------------------------------------------------------|---------|--------|
| T1 | the command and its state      | core/cmd/review.sh, core/lib.sh                                                          | 400     | done   |
| T2 | the review file and its rubric | templates/review.md, templates/review/STANDARDS.md, core/cmd/init.sh                     | 260     | done   |
| T3 | the hand-off and the loop      | core/cmd/commit.sh, core/cmd/help.sh, templates/AGENTS.md, templates/workflow.md         | 160     | done   |
| T4 | the rules that hold it         | .leo/rules/REVIEW-VOCAB.md, .leo/rules/REVIEW-TRACKED.md, .leo/rules/FLOW-DOCUMENTED.md  | 110     | done   |
| T5 | tests for the whole cycle      | t/smoke.sh                                                                               | 95      | done   |
| T6 | the documents and the record   | README.md, GUIDE.md, VERSION, .leo/plans/ROADMAP.md, .leo/plans/C10-review/plan.md        | 310     | done   |
| T7 | a Claude Code front door       | .claude/commands/review.md, .claude/agents/code-review.md                                 | 230     | done   |

Status: pending -> in-progress -> done.

## Budget
est: 1565 LOC
