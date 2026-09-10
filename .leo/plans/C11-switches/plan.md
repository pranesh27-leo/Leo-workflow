# Plan: C11 deferred commits, and tool switches that switch

Created: 2026-09-10

## Goal
Stop asking "is the change done?" once per cycle, and make a declared tool a
switch rather than a label.

## Non-goals
Supervising the agent. leo runs before and after it, never around it, and
cannot make it call a tool or stop it. Installing, launching or configuring
anything. A plugin framework: an adapter stays four shell functions.
Guessing at Cursor's, Codex's or Aider's skill paths.

## Wrong-change signal
If enforcement ever needs leo to sit between the agent and its tools — a
wrapper, a proxy, a daemon — this is the wrong shape. The only evidence leo
can use is the mark a tool leaves behind, the way the grill already works.

## Tasks
| ID | Task | Files | Est | Status |
|----|------|-------|-----|--------|
| T1 | record a cycle's message without committing it | core/cmd/record.sh, core/cmd/commit.sh, core/lib.sh | 260 | done |
| T2 | scan and check from the last record, not HEAD | core/cmd/scan.sh, core/cmd/check.sh, core/lib.sh | 120 | done |
| T3 | announce a tool, and log that it was announced | core/cmd/use.sh, core/lib.sh | 200 | done |
| T4 | fail a check when the switch and the evidence disagree | core/cmd/check.sh, core/integrations/*.sh | 180 | done |
| T5 | install skills where the runtime reads them | core/cmd/init.sh, .leo/rules/SKILLS-REACHABLE.md | 90 | done |
| T6 | the bugs dogfooding found | core/lib.sh, core/cmd/check.sh, .leo/rules/COMMANDS-DOCUMENTED.md | 150 | done |
| T7 | say all of it in the documents | GUIDE.md, README.md, DEMO.md, templates/*, core/cmd/help.sh | 450 | done |

## Budget
est: 1450 LOC
