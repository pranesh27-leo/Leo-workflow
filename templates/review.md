# Review: <REV> — <SUBJECT>

Standards: `.leo/review/STANDARDS.md`

This is cycle two. The change is already committed; nothing here can be fixed
by editing it. A finding becomes either a new dev cycle or a waiver, and both
are the developer's call.

<!--
The findings table. One row per finding, and a finding earns its row by being
actionable — see "Writing a finding" in the standards.

  | 1 | blocker     | `api/auth.go:88` | token compared with == | timing oracle: an attacker recovers the token byte by byte. Use a constant-time compare | open |
  | 2 | improvement | `api/rate.go:12` | the limiter map is never evicted | one entry per API key, forever — memory grows with traffic and never comes back | open |
  | 3 | nit         | `api/rate.go:40` | `n` is the burst size | a name that says so saves the next reader the lookup | open |

Severity is one of `blocker`, `improvement`, `nit`. Status is one of `open`,
`fixed`, `waived`. `leo review --close` reads both columns, so the words are
fixed.

An open blocker holds the review open. `fixed` means a later commit fixed it —
name that commit in the Fixed-by line below. `waived` is the developer
accepting it, never the reviewer, and the reason travels with the review.
-->

| # | Severity | Where | Finding | Why it matters | Status |
|---|----------|-------|---------|----------------|--------|

Verdict: <ship | fix-first> — <one line: what you read, and what you concluded>
Fixed-by: <shas of the commits that closed the blockers, or "-">
Closed: -

## Read first

<The 2-3 places a human should look before anything else: widest blast radius,
anything security-relevant, and any judgement call the developer has not seen.
Name them even when you found nothing wrong with them — "I looked here and it
is fine" is information, and it is the part a reviewer can be held to.>

## What was asked for

<!--
Assembled by `leo review` from the dev cycle: the commit message leo wrote
(goal, manifest, session) and the plan and task files still on disk. Read it
before the diff. A review that does not know what was asked for can only check
the code against itself, which is how a change that is internally consistent
and completely wrong passes.

Do not edit this section. If it is thin, the dev cycle was thin, and that is
itself the first finding.
-->

<CONTEXT>

## Signals

<!--
Written by `leo review` from the diff. Deterministic, no judgement, no tokens:
it says where to look, never what to think. A signal is not a finding — most
of them will be nothing, and clearing one costs a glance.
-->

<SIGNALS>
