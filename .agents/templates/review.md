# Review: G<n> — <name>

Reviewed: <date>
Diff: <what was read: `git diff`, or a range>
Tests: `<command>` — <the real result, pasted, not summarised>

## Done when

<!-- One row for the goal, one for every task. Met or not met, and the
     evidence: a `path:LINE`, a test name, or a command and what it printed.
     A row with no evidence is not met. -->

| What | Done when | Met? | Evidence |
|------|-----------|------|----------|
| G<n> | <the goal's Done when> | <met / not met> | <evidence> |
| T<n> | <the task's Done when> | <met / not met> | <evidence> |

## Findings

<!-- Anything that works, but not in the way the goal asked for. Every `-`
     row in the manifest is a finding.
     Severity: blocker | improvement | nit
     Status:   open | fixed | waived -->

| # | Severity | Finding | Where | Status |
|---|----------|---------|-------|--------|
| 1 | <sev> | <what is wrong, and why it matters> | `<file>:<line>` | open |

## Independent check

<!-- What a fresh reviewer found, given only the diff and the manifest: the
     leo-reviewer subagent in Claude Code. Paste its findings, not your
     summary of them. No subagent in this runtime? Say so here. -->

## Read this first

<!-- The hunks in reading order, riskiest first: where the logic lives, then
     every `default` row from the manifest, then the rest. One line each. -->

| # | Hunk | What to look for | Source |
|---|------|------------------|--------|
| 1 | `<file>:<line>` | <the one thing to check here> | <grill / pattern / default> |

## Your understanding

<!-- Two or three questions the diff answers, asked before the green signal.
     Their answer in their words, then the code's answer with its line.
     A wrong answer shows what to explain before they say yes.
     `skip` is an answer: write it down. -->

| # | Question | Their answer | The code says |
|---|----------|--------------|---------------|
| 1 | <what breaks if row 3 is deleted?> | <in their words> | <`path:LINE` and what it shows> |

## Green signal

<!-- Ask the developer: "Is this the result you wanted?"
     Write their answer here, in their words, with the date. Yes is the
     green signal and only then is the commit message drafted. No is a
     replan. -->
