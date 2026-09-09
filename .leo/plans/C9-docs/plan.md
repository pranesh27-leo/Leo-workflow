# Plan: make the documents describe the tool that exists

Created: 2026-09-09

## Goal
Five changes landed in two days and the documents did not keep up. DEMO.md
shows `leo check` output with no `grill` stage — a section that now sits
between manifest and budget in every run — and names neither subtasks nor
`--verbose`. README describes the loop without the subtask stage. Someone
following either document today sees output that does not match their
terminal, which is the fastest way to lose their trust in the rest of it.

Also: give the daily loop a single place to be read as instructions, rather
than only as a 900-line walkthrough.

## Non-goals
- **No security audit.** Explicitly out at the developer's instruction, twice.
  It stays on the roadmap as C3, unstarted, and this plan does not touch it.
- No third document. GUIDE.md is the human's, AGENTS.md is the agent's, and
  DEMO.md is the worked example. A fourth would be a fourth thing to drift.
- No re-run of the DEMO transcript. Its numbers came from a real session
  against click; inventing fresh output would be worse than a stale example
  honestly labelled.

## Wrong-change signal
Any command output pasted into a document that was not produced by running it.
The value of DEMO.md is that it is a transcript; the moment it contains
plausible-looking invented output it is worth less than nothing.

## Tasks

| #  | Task                                                        | Files       | Est LOC | Status  |
|----|-------------------------------------------------------------|-------------|---------|---------|
| T1 | tests: docs name every stage and flag, and match real output | t/smoke.sh  | 45      | done    |
| T2 | DEMO.md: the grill stage in check output, subtasks, --verbose | DEMO.md    | 70      | done    |
| T3 | README: the daily loop as instructions you can follow         | README.md   | 60      | done    |
| T4 | GUIDE: remaining gaps against the current tool                | GUIDE.md    | 40      | done    |

## Budget
est: 215 LOC
