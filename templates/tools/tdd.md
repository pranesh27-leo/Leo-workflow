# TDD — the test comes first

Not a tool. The only capability on leo's list that is a practice, which is why
it sits under `practice` rather than beside the things that mediate what you
see.

## The loop

1. Write the test from the task's **Done when** — the spec, not the
   implementation. If you cannot write it, "Done when" is not observable yet;
   fix that first.
2. Run it. **Watch it fail.** A test that passes before you write anything is
   testing nothing, and this step is the entire point of the practice.
3. Confirm it failed *for the reason you expect*. A test failing on a typo, an
   import error or a missing fixture is not red — it is broken.
4. Implement the smallest thing that makes it pass.
5. Run it. Watch it pass.
6. Set the task to `done` in `.leo/plan.md`.

`leo task` seeds a task's to-do with exactly those steps while this is on.

## Installed means TEST_CMD is set

Test-first needs something to run. Without `TEST_CMD` in `.leo/config` there is
nothing to watch fail, so leo reports the capability as MISSING rather than
showing a green light it cannot back. `leo install tdd` will not guess a test
command for you — that is config, and leo does not write config nobody
approved.

## What the switch does and does not do

It governs **order**, and only order.

With TDD off you may write the test afterwards. You may not skip it. `leo
check` runs `TEST_CMD` and records the result in the manifest either way, no
mode can turn that off, and the result lands in the commit message. Tests are
an engineering control; the order they are written in is a preference.
