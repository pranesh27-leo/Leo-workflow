# Plan: <name>

## Goal
<One sentence: what changes, and why.>

## Non-goals
<What this change does not touch. This is what stops scope creep, and it is
what cycle two checks a hunk against.>

## Wrong-change signal
<The one observation that would mean this is the wrong change entirely. If
you see it, stop and say so rather than finishing the plan.>

## Tasks

| #  | Task   | Files   | Est LOC | Status  |
|----|--------|---------|---------|---------|
| T1 | <task> | <files> | <n>     | pending |
| T2 | <task> | <files> | <n>     | pending |

Status: `pending` -> `in-progress` -> `done`, or `later`.

Task ids never restart. If the last plan ended at T7, this one starts at T8 —
so `T8` names one task in this repository forever, and a manifest row saying
`T8` is unambiguous years later.

## Later
<!-- One line per deferred task, with its reason:
     - T3 — waiting on the vendor's key  (2026-09-25)
     A deferral with no reason is indistinguishable from a task somebody
     forgot, which is the whole point of writing it here. -->

## Budget
est: <n> LOC
