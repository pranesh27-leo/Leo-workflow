# leo

## What this is

A command-line tool that makes AI-written code reviewable, by refusing to let
the diff be the only record of what happened. A **plan** says what the change
was allowed to be. A **manifest** says, for every hunk, which task it serves,
why that task requires it, and what breaks without it. Both end up inside the
commit message, so `git log` answers "why is this line here" years later with
no AI in the loop.

It is one bash script and a directory of bash scripts. It has no runtime
dependencies beyond git and POSIX tools, no network access, no daemon, and no
state outside `.leo/` in the repository it is run in.

What depends on it: whoever has to review or maintain code an agent wrote. If
leo is wrong, the failure is not a crash — it is a check that passes while the
thing it checks is absent, which is the failure mode almost every rule in
`.leo/rules/` was written after.

## Shape of the code

See `ARCHITECTURE.md`. The three paths worth knowing before anything else:

- `src/lib/` — every shared fact, one file per concern. Read the header
  comments; each is organised
  by noun (repo, plan registry, tasks, subtasks, records, reviews, session,
  tools, exit hooks, session doc).
- `src/cmd/` — one file per command, no registry. The file's header comment
  is the documentation.
- `.leo/rules/` — ten rules, each with a shell check `leo check` runs. Every
  one of them was written after a real bug; the "Learned from" line names it.

## Non-obvious rules

- **Never add a dependency.** bash 3.2, POSIX coreutils, git. Not jq, not
  node, not `sed -i`, not a GNU-only flag. macOS ships bash 3.2 and BSD awk.
- **Never read `$LEO_HOME/templates` directly** — go through `tmpl_cat`. A
  direct read works in a clone and breaks only for whoever vendored a
  single-file build, which is the one place nobody looks. `ASSET-SEAM` catches
  it.
- **Never `process.on('exit')`** outside `src/lib/exit.js` — use `atexitAdd`.
  Traps do not stack. `ONE-EXIT-TRAP` catches it.
- **Never grow `AGENTS.md`** without reading `.leo/rules/ALWAYS-LOADED.md`
  first. Those bytes are re-read on every request of every session forever,
  and the measurements are in `.leo/plans/C5-benchmark/RESULTS.md`.
- **Guard every substitution that can legitimately match nothing.** Under
  `set -e` with `pipefail`, a grep with no match kills the command after the
  value was already computed, silently.
- **A new command is a new file** — and then a `leo help` entry and a GUIDE.md
  entry, or `COMMANDS-DOCUMENTED` fails.

## Vocabulary

| Word | Means here |
|---|---|
| **cycle one** | build it: grill, plan, task, subtask, build, manifest, record |
| **cycle two** | read it: a review of a commit that already landed. Cannot edit code. |
| **record** | a finished cycle's commit message, filed and not landed |
| **hunk** | one contiguous change, one row of the manifest |
| **grill** | the interview before a task is built. No cap on questions; zero is not a grill. |
| **later** | a fourth task status: not done, not abandoned, skipped by the loop |
| **capability** | a tool leo can name, switch and check evidence for — never install |
| **invoked / ambient / practice** | the three kinds of capability, by what evidence each leaves |
| **plan P1, P2** | one change each. Task ids never restart across them. |

## Decisions that are already made

- **leo does not commit.** An agent runs `leo record`; a human runs
  `leo commit`. This is not configurable and will not become configurable.
- **leo does not install anything** except through `leo install`, which prints
  the command and requires a terminal.
- **No token or savings figures.** The tools leo names measure different things
  over overlapping buffers; summing them produces a number that is false.
- **No cap on grill questions.** The vendored skill's stop condition is shared
  understanding, confirmed by the developer. leo says *when* to grill, never
  how much. Any number stated anywhere in this repository is leo overriding
  something it vendored unmodified.
- **Task ids are globally unique and never restart.** A per-plan counter would
  be tidier and would make `T1` ambiguous the moment a second plan existed.
- **`.leo/plans/` is tracked; everything else under `.leo/` is not.** The rest
  ends up inside the commit message it describes. A plan is the reasoning
  behind a change, it outlives the change, and it belongs to everyone who later
  has to ask why.
