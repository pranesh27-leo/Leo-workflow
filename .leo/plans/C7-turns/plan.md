# Plan: spend fewer turns, print less into context

Created: 2026-09-09

## Goal
Cost is quadratic in turn count — halving a session costs 33%, not 50%,
because every turn re-reads everything before it. leo trims bytes and adds
turns, which is the wrong axis. Tell people to restart the session between
tasks (worth ~7x on measured growth rates), and stop printing 26 lines into
context every time a check succeeds.

## Non-goals
- **leo does not read Claude Code transcripts.** `CLAUDE_CODE_SESSION_ID` is
  set and the transcript is right there, so leo *could* count this session's
  turns and nag precisely. It will not: leo names Codex, Cursor, Aider and
  Gemini in its own templates, and a headline feature that works for one agent
  and silently does nothing for the rest is worse than no feature. The reader
  stays in `t/`, marked as an instrument.
- No hard gate on session length. leo cannot verify you restarted, and a check
  you cannot satisfy by doing better work is one people learn to bypass.
- No batched ceremony command, and no change to what `leo scan` prints. Both
  are real savings and both are smaller; bundling four levers means not
  knowing which one moved the number.
- No change to failure output. Failures are rare and the detail is the point.

## Wrong-change signal
The restart advice lands in AGENTS.md as a paragraph. Guidance about reducing
per-request context, placed in the file that is re-read on every request, pays
for itself in the wrong direction. One line there, the reasoning on demand.

## Tasks

| #  | Task                                                         | Files                          | Est LOC | Status  |
|----|--------------------------------------------------------------|--------------------------------|---------|---------|
| T1 | smoke assertions for terse output and the nudge, failing first | t/smoke.sh                   | 55      | done    |
| T2 | `leo check` terse on success, `--verbose` restores            | core/cmd/check.sh              | 70      | done    |
| T3 | the restart nudge, fired where leo can actually see it         | core/cmd/commit.sh, core/cmd/task.sh | 45 | done    |
| T4 | one line in AGENTS.md, the reasoning in workflow.md            | templates/AGENTS.md, templates/workflow.md | 50 | done    |
| T5 | docs and help follow the new default                           | GUIDE.md, DEMO.md, core/cmd/help.sh | 45 | done    |
| T6 | RESULTS.md records this as predicted, not measured             | .leo/plans/C5-benchmark/RESULTS.md | 35  | done    |
| T7 | fixtures stop depending on gitignored task files from a past change | t/fixtures/, t/fixtures/generate.sh | 40 | done    |

## Budget
est: 340 LOC

T7 was unplanned: clearing .leo/tasks/ for this change would have silently
emptied the benchmark's task comparison, because generate.sh reads working
state that belongs to a change finished days ago.
