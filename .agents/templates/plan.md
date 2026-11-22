# G<n> / plan-<n>: <name>

## Goal
G<n> — <the goal, from goal.md>. This plan delivers: <the part this phase
delivers, when the goal has more than one plan>.

## Non-goals
<What this change does not touch. This is what stops scope creep, and it is
what the review checks a hunk against.>

## Wrong-change signal
<The one observation that would mean this is the wrong change entirely. If
you see it, stop and say so rather than finishing the plan.>

## Tasks

| #  | Task   | Files   | Est LOC | Status  |
|----|--------|---------|---------|---------|
| T1 | <task> | <files> | <n>     | pending |
| T2 | <task> | <files> | <n>     | pending |

Status: `pending` -> `in-progress` -> `done`, or `later`.

Task ids never restart, across plans and goals. If the last plan ended at
T7, this one starts at T8, so `T8` names one task in this repository forever.
Each task file is `tasks/T<n>.md` beside this plan.

## Later
<!-- One line per deferred task, with its reason:
     - T3 — waiting on the vendor's key  (2026-09-25)
     A deferral with no reason is indistinguishable from a task somebody
     forgot, which is the whole point of writing it here. -->

## Budget
est: <n> LOC

## Change log
<!-- Every change made after the developer approved this plan. One line each:
     - 2026-11-22 — dropped T4, added T9 — <why, in the developer's words>
       (grilled: see goal.md ## Grill, 2026-11-22)
     A plan changed with no entry here is a plan nobody can review. -->
