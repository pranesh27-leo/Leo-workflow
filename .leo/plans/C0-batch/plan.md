# Plan: the batch in this working tree

Created: 2026-09-09

## Goal
Four changes were built back to back without an intervening commit, so this
tree holds all of them at once. This plan exists to describe the tree that
actually exists, so the manifest has task IDs to point at and nothing gets
reviewed against a plan it was not part of.

## Non-goals
- Not a replacement for the four plans. `C1`, `C2`, `C4`, `C5` are the real
  reasoning; this is only the batch wrapper.
- No new work. Every row here is already built.

## Wrong-change signal
Committing this as one commit. The repo's own convention is one change per
commit, and four changes in one message means `git log` can never answer
"why is this line here" for any of them.

## Tasks

| #  | Task                                                        | Files                                  | Est LOC | Status |
|----|-------------------------------------------------------------|----------------------------------------|---------|--------|
| T1 | MIT licence (C1)                                             | LICENSE, README.md                     | 25      | done   |
| T2 | single-file build, asset seams (C2)                          | leo, core/, GUIDE.md, t/smoke.sh       | 420     | done   |
| T3 | grill every task, AGENTS.md that binds (C4)                  | templates/, core/cmd/                  | 500     | done   |
| T4 | token benchmark, three instruments (C5)                      | t/bench*.sh, t/fixtures/               | 455     | done   |
| T5 | always-loaded cost controls, from the benchmark's finding    | templates/AGENTS.md, .leo/rules/       | 200     | done   |
| T6 | the local plan store itself                                  | .leo/plans/                            | 250     | done   |
| T7 | turn-cost work: terse check, restart nudge (C7)               | core/cmd/check.sh, core/cmd/commit.sh  | 340     | done   |

## Budget
est: 2190 LOC

Sum of the four plans (1400) plus the plan store and the cost controls, which
no plan priced because both came out of work that was already underway — the
store from a request mid-change, the controls from the benchmark's result.
