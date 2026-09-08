# Results — 2026-09-09

Instrument: `t/bench-session.sh --all`, reading Claude Code transcripts from
`~/.claude/projects/`. Counts are the ones the API reported per turn, not
estimates. Model: Claude Opus 5 (`claude-opus-5`) for the leo sessions.

**Sample:** 16 sessions of 20+ turns across 9 projects on one machine —
4 with leo (1,076 turns), 12 without (2,767 turns).

## The headline

**leo came out roughly 17% more expensive per turn.** Not the result the tool
was hoping for, and it is the one the record shows.

| | fresh/turn | cached/turn | output/turn | price-weighted/turn |
|---|---|---|---|---|
| with leo    | 3,726 | 162,164 | 1,382 | $0.1335 |
| without leo | 6,370 |  92,331 | 1,066 | $0.1140 |

Medians across sessions, not means — one 464k-cached-tokens/turn session would
otherwise have decided the answer by itself.

## What is actually happening

The two token classes move in **opposite directions**, which is why a single
"tokens saved" number would have been worse than no number at all:

- **Fresh tokens: leo uses 1.71x fewer.** This is the manifest, the plan and
  the task file doing exactly what they were built to do. Real, and worth
  having.
- **Cached tokens: leo uses 1.76x more.** AGENTS.md, the workflow, the plan,
  the task file and the tool docs sit in context and are re-read every single
  turn. leo's own record is the thing being re-read.

Cache re-reads are ~95% of all token volume, so the second effect swamps the
first even at a tenth of the price.

## The result depends on an assumption, and it flips

Cache reads are priced at 0.1x input on the Claude API. The verdict turns on
that number, and it flips inside the plausible range:

| cache read priced at | ratio | verdict |
|---|---|---|
| 0.05x input | 1.02x | leo cheaper |
| **0.10x input (actual)** | **0.85x** | **leo dearer** |
| 0.20x input | 0.75x | leo dearer |
| 1.00x input | 0.61x | leo dearer |
| cache ignored entirely | 1.30x | leo cheaper |

Anyone quoting "leo saves 30% of tokens" is quoting the last row — true, and
true only if you pretend the cache is free.

## Why this is weak evidence

**It is observational, not an experiment.** leo was chosen for the projects it
was used on, not assigned to them. Three of the four leo sessions are this
repository, which carries a 43k-line GUIDE.md and dense documentation — a big
context for reasons that have nothing to do with leo. The non-leo sessions are
firmware design, app work and learning repos.

Per-turn is also a debatable normalisation. leo adds turns by design (the
grill is turns), so per-turn flatters it relative to per-task; per-task
flatters it the other way if leo needs fewer attempts. Neither is available
from transcripts alone.

**What would settle it:** the same task, twice, in two clean worktrees off the
same commit — `PROTOCOL.md`. Until someone runs that, this file is a
hypothesis with numbers attached.

## What to do about it

The finding points at a fix rather than a retreat. leo's cost is **per-request
loaded context**, not per-change artifacts, so:

- Keeping AGENTS.md under 50 lines is not tidiness, it is the main cost lever.
  It is paid on every request of every session, forever.
- `.leo/workflow.md` being read on demand rather than loaded is worth more
  than any manifest saving.
- The tool docs (`.leo/tools/*.md`) are gated behind ON capabilities already.
  That gate is a cost control, and it should stay one.
- **The honest pitch is reviewability, not cheapness.** leo makes AI-written
  code reviewable; on this evidence it does not make it cheaper. Selling it on
  tokens invites exactly this benchmark, and this benchmark says no.

---

# Follow-up — 2026-09-09: acting on the finding

The result said leo's cost is per-request loaded context, not per-change
artifacts. Three changes followed, none of which touch what the agent is told
to do.

## What changed

`AGENTS.md` was compressed from 2,170 to 1,721 bytes — **every instruction
kept**, only the prose tightened, and the editing note that lived in an HTML
comment moved into the rule that enforces the budget. It was costing tokens on
every request to tell whoever edits the file how to edit it.

| | before | after | |
|---|---|---|---|
| always-loaded (AGENTS.md + CLAUDE.md) | 2,380 b | 1,931 b | **-19%** |
| over one 209-turn session | 497,420 b | 403,579 b | **-93,841 b** |

209 turns is the median session length on this machine, from real transcripts.

`.leo/rules/ALWAYS-LOADED.md` now enforces all three levers, and each arm was
tested by breaking it deliberately:

1. **A byte budget** (2,400 b) on the always-loaded pair. Bytes, not lines —
   a line cap is defeated by long lines and the model pays for bytes.
2. **No imports from AGENTS.md.** The failure this prevents is one line:
   adding `@.leo/workflow.md`. It looks helpful and silently multiplies 10KB
   by every request anyone ever makes.
3. **Tool docs pointed at, never printed.** `leo session` emits a path. The
   seven docs are 11,775 b; inlining one would put it in context for a session
   that may never use that tool.

`t/bench-context.sh` measures the footprint directly, because
`t/bench-session.sh` reads transcripts and therefore cannot see a change made
this morning. It reports the always-loaded pair costs **7x more over one
session** than every on-demand file in leo put together, read twice each.

## What did not change, and will not yet

The session numbers above are **unchanged and will stay unchanged** until new
sessions are run. Transcripts are a record of what happened; editing a template
today does not rewrite them. Anyone re-running `t/bench-session.sh --all` right
now sees the same 0.85x, and that is correct behaviour, not a broken tool.

Re-measuring honestly needs new sessions under the smaller footprint, and the
controlled A/B in `PROTOCOL.md` regardless. A -19% cut to a component that is
~95% of volume should move the ratio, but "should" is a prediction, and this
file exists because a prediction was worth less than a measurement.

---

# Follow-up 2 — 2026-09-09: the turn count, and what is still unproven

Trimming AGENTS.md by 19% barely moves the bill, and measuring why produced
the most useful number in this file.

## Cost is quadratic in turns

Every turn re-reads every turn before it, so context size grows linearly and
total spend grows with the square. From session `87524172` (357 turns):

| turn | context |
|---|---|
| 0 | 2 |
| 107 | 150,819 |
| 356 | 323,864 |

Total read across the session: **69,530,108 tokens**. The first half of it
accounts for only 33% of that. Halving a session does not halve its cost —
it cuts it to a third.

**Bytes are linear. Turns are quadratic.** leo trims bytes and adds turns
(grill rounds, per-task ceremony, scan/check cycles). That is the deviation,
and it is why the byte work was worth so little.

## Where leo's own output goes

Of 508,410 bytes of tool output resident in this project's sessions, **85,317
(16.8%) is leo's own commands** across 171 calls. `leo check` was the largest
single contributor at 24,097 bytes — it printed 26 lines every time it passed,
and a passing check is the least informative thing leo prints.

## What was changed (C7), and what it is worth

`leo check` is now quiet on success (26 lines to 3) with `--verbose` to
restore, and `leo commit` ends by telling you to start a fresh session.

**Both numbers below are PREDICTED, not measured.** The quadratic arithmetic
is solid; the 7x is extrapolation from one session's growth rate, not an
experiment:

- one session per task instead of one per change: **~7x**, predicted
- terse check output: a few hundred bytes per call, not re-read afterwards —
  real but small, and unmeasured

Nobody should quote either as a result. The A/B that would settle the first
one now has an obvious shape — same task, one long session versus one session
per task — and it is written up in `PROTOCOL.md`.

## What leo deliberately did not do

`CLAUDE_CODE_SESSION_ID` is set in the environment, and it maps to a
transcript leo could read to know exactly how long the current session has run
and nag precisely. That was available and was rejected: leo names Codex,
Cursor, Aider, Windsurf and Gemini in its own templates, and a headline
feature that works for one agent and silently does nothing for the others is
worse than no feature. The transcript reader stays in `t/`, as an instrument.
