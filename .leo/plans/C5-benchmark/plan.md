# Plan: measure the token saving against real Claude counts

Created: 2026-09-08

## Goal
leo claims a manifest is cheaper to review than a diff and a task file cheaper
than whole-file context. Neither number exists. Measure both with Anthropic's
`/v1/messages/count_tokens`, on fixtures, and report absolute counts with the
ratio -- so the claim is either true or retired.

## Non-goals
- Never runs in `leo check` or the smoke suite. It needs a key and a network,
  and both would make the test suite fail on a plane.
- Never runs against a user's source. Fixtures only. C3 spends a whole change
  proving no tool ships your code anywhere; a benchmark that shipped your diff
  to an API would make that hypocrisy.
- No percentage in leo's own output. The plan format already forbids it.
- Not a CI gate. A number that fails a build is a number people game.

## Wrong-change signal
The benchmark reports a saving computed from an estimate (chars/4) while
claiming to be a real count. Either it called the API or it did not say.

## Two instruments, and the second one is the real one

**`t/bench-session.sh` — end to end, local, no key.** Claude Code already
writes every session to `~/.claude/projects/<slug>/*.jsonl`, and every
assistant turn carries the usage the API itself reported: input, output,
cache reads, cache writes, thinking. That is ground truth for what a session
actually cost, and it needs no API key, no network and no estimate. Sessions
are classified as with-leo or without-leo by whether leo commands appear in
them — read off the record rather than remembered.

**`t/bench.sh` — artifact sizes, needs a key.** Counts the manifest against
the diff, and the task file against the files it names:

    raw `git diff`            vs  `leo scan` manifest
    whole-file context        vs  the task file for that task

This one is a proxy, and a flattering proxy. It counts everything leo saves
and nothing leo spends: AGENTS.md loads on every request forever, and the
workflow, the plan, the task file and the grill rounds are all tokens leo
added. A manifest 8x smaller than its diff proves nothing if the agent read
the diff anyway. Keep it — artifact size is worth knowing — but never quote
it as the saving.

## What the first measurements showed

Three real sessions in this repository: 800k–1.2M fresh tokens each, against
23M–70M cache reads. **Cache re-reads are 95%+ of everything spent.** Any
claim about saving tokens that ignores cache economics is measuring a rounding
error. This is the strongest argument for the session instrument over the
artifact one, and it was invisible until the transcripts were read.

All three sessions used leo, so there is no control group yet and no ratio to
report. The tool says so rather than dividing two unrelated numbers.

## Tasks

| #  | Task                                                  | Files             | Est LOC | Status  |
|----|-------------------------------------------------------|-------------------|---------|---------|
| T1 | fixtures: three repos, small, medium, sprawling        | t/fixtures/       | 90      | done    |
| T2 | count_tokens client; skips loudly with no key          | t/bench.sh        | 80      | done    |
| T3 | the two comparisons, absolute counts and ratio         | t/bench.sh        | 70      | done    |
| T4 | session instrument: read transcripts, classify, compare | t/bench-session.sh               | 95      | done    |
| T5 | the A/B protocol, written down so it can be repeated    | .leo/plans/C5-benchmark/PROTOCOL.md | 60   | done    |
| T6 | results, with the model and date they used             | .leo/plans/C5-benchmark/RESULTS.md | 40      | done    |

## Budget
est: 455 LOC

300 was priced before the session instrument existed. The artifact
benchmark was the whole plan; measuring real consumption was not considered,
and it is the half that answers the question actually asked.
