---
name: tdd
description: Test-driven development. Write the test, watch it fail for the reason you expect, then make it pass. Use when the session declares TDD is on.
---

# Test first

The order is the whole thing. Not "write tests" — **write the test before the
code exists, and watch it fail**.

## The four steps

1. **Write the test from "Done when".** The task file states an observable
   condition; the test is that condition, executable. Test the behaviour the
   task promises, not the implementation you are about to write.

2. **Run it. Watch it fail.** Read the failure. It must fail **for the reason
   you expect** — the assertion you wrote, not an import error, not a typo,
   not a missing fixture. A test that fails for the wrong reason has told you
   nothing, and a test that *passes* here is testing something that already
   worked.

   This step is the only one that cannot be recovered later. Steps 1, 3 and 4
   leave artefacts you can inspect afterwards; this one leaves nothing but
   your word. Say what the failure said.

3. **Make it pass, minimally.** The smallest change that turns this test
   green. Not the design you can see coming — that is the next test's job,
   and the next test will tell you whether you were right about it.

4. **Run it. Watch it pass.** And run the rest of the suite: green here and
   red two files over is a change, not a fix.

## Why the order and not the coverage

A test written after the code passes on the first run. It was shaped by the
implementation it is testing, so it tests what the code *does* — including
the bugs, which are now pinned in place and green.

A test written first cannot be shaped that way, because there is nothing to
shape it. It can only describe what you meant.

## What counts as a failing test

Run it and read the output.

- **Right:** the assertion fires. `expected 429, got 200`.
- **Wrong:** `ModuleNotFoundError`, `SyntaxError`, a fixture that does not
  exist, a typo in the test name. Fix those and run again — you have not
  seen the test fail yet.
- **Also wrong:** it passes. Either the behaviour already exists, or the test
  does not test what you think. Find out which before writing a line of
  implementation.

## When it does not apply

**A spike.** Exploring whether something is possible is not building it.
Throw the spike away and start at step 1 — do not keep it and add tests
after, because that is the after-the-fact test with extra steps.

**A change with no observable behaviour.** A rename, a move, a comment. The
existing suite passing is the test.

**Something genuinely hard to test first** — a rendering detail, a timing
race, a third-party integration with no sandbox. Say so, say why, write the
test you can, and do not pretend the order was followed when it was not.

## Reporting it

Say which of the four steps you did. If you skipped step 2 — if you wrote the
code first, or never watched it fail — **say that in your first line**. Not as
an apology; as a fact the developer needs, because it changes how much the
green tick is worth.

Nothing here is enforced by a program. An agent that writes the test
afterwards and reports otherwise is invisible to this file, and the only
thing standing against that is that the developer asked for TDD and is
entitled to a straight answer about whether they got it.
