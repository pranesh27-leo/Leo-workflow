# leo, on a real project

Everything below is recorded output from one session against
[`pallets/click`](https://github.com/pallets/click) at `36baa15ff831`
(2026-08-27), version `8.5.1.dev0` — 17 modules, 47 test files, 1990 tests.

The defect is real and was found by reading the source, not planted.
`click.Path.to_info_dict()` declares eight attributes on the class and reports
six. `to_info_dict` is the public introspection API that documentation
generators and shell-completion tooling read, so a `Path` that could be
`executable=True` looked like one that could not:

```python
>>> p = click.Path(executable=True, resolve_path=True)
>>> sorted(k for k in p.to_info_dict() if k not in ("param_type", "name"))
['allow_dash', 'dir_okay', 'exists', 'file_okay', 'readable', 'writable']
>>> [a for a in ("executable", "resolve_path") if a not in p.to_info_dict()]
['executable', 'resolve_path']
```

Nothing on this page is retouched. leo rejected this change three times before
it landed, and all three refusals are here.

---

## 1. Adopt leo

```
$ leo init
  install AGENTS.md
  install CLAUDE.md
  install .leo/workflow.md
  install .leo/rules/EXAMPLE.md
  install .leo/integrations/README.md
  install .leo/config
  update  .gitignore (.leo/plan.md)
  update  .gitignore (.leo/manifest.md)
  update  .gitignore (.leo/session)

ok   ready
  1. fill in AGENTS.md — delete every placeholder you do not need
  2. set TEST_CMD in .leo/config
  3. start a change: leo plan "<name>"
```

`TEST_CMD` then goes in `.leo/config`. Without it leo can check that a change
was scoped honestly, but not that it works — and the whole demo turns on that
distinction.

---

## 2. Declare the session

This is a bug hunt, so: `debugging`. The mode is not a preference. It decides
whether the tools sitting between the agent and the code may summarise what it
sees, and during a bug hunt the line that matters is routinely the line that
looks like noise.

```
$ leo session --mode debugging

leo session
  Mode: debugging

code intelligence
  Serena        ON
  Code graph    ON

efficiency
  RTK           ON
  Headroom      OFF
  Ponytail      OFF
  Caveman       OFF

practice
  TDD           ON

engineering controls
  Plan          ON   always
  Task IDs      ON   always
  Manifest      ON   always
  Rules         ON   always
  Tests         ON   always
  Human commit  ON   always

dependencies
  Serena        MISSING
      instructions: .leo/tools/serena.md
      uv tool install -p 3.13 serena-agent
      claude mcp add serena -- serena start-mcp-server --context claude-code --project "$(pwd)"
  Code graph    MISSING
      instructions: .leo/tools/graph.md
      curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash
      the installer registers the MCP server with Claude Code itself
  RTK           MISSING
      instructions: .leo/tools/rtk.md
      brew install rtk        (or: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh)
      rtk init -g             installs the auto-rewrite hook
  TDD           installed
      instructions: .leo/tools/tdd.md
      red before green: the test fails first, for the reason you expect
      leo task seeds the to-do with those steps while this is on

warn 3 enabled capability(s) not installed — leo works without them
  install one above, or drop it here: leo session --<name> off
  leo does not install these. Declaring one does not switch anything on.
```

Serena and the code graph are on: understanding is the bottleneck here. TDD is
on as well, and click has a `TEST_CMD`, so it reads as installed — the fix gets
written as a failing test first.
Headroom, Ponytail and Caveman are off — those compress, shorten and minimise,
and this is the mode where none of that is wanted.

The engineering controls sit below them and say `always`. No mode can reach
them, and there is no key for them in `.leo/session`.

Three tools are missing. leo says so and carries on. Nothing here is a gate.

---

## 3. Install what the mode declares

```
$ leo install

leo install
  serena        missing     ON
  graph         missing     ON
  rtk           missing     ON
  headroom      missing     OFF
  ponytail      missing     OFF
  caveman       missing     OFF
  tdd           installed   ON

  leo install <name>     install one
  leo install --all      install everything this session declares
```

An agent that tries to install gets stopped:

```
$ leo install graph   # as an agent, with no terminal
ERR  leo install needs a human at a terminal

If you are an agent: do not install anything. Show the developer
`leo install` and let them decide what goes on their machine.

If you are a human whose shell has no tty: LEO_YES=1 leo install ...
exit=2
```

That is the same refusal `leo commit` gives, for the same reason. Run by a
human, leo prints the command it is about to run — chosen for this machine, not
a menu of what might happen — and asks before running it:

```
$ leo install ponytail   # a human, at a terminal, answering y

install ponytail
  leo will run this. It is not leo's code, and leo has not audited it:

      printf '\n' >> AGENTS.md
      curl -fsSL https://raw.githubusercontent.com/DietrichGebert/ponytail/main/AGENTS.md >> AGENTS.md

ok   ponytail installed
      the plan outranks it: a task that asks for an abstraction gets the abstraction
      an honest '-' row in the manifest is still the stronger check
exit=0
```

leo re-checked `ponytail_present` afterwards and printed the adapter's advice.
The other three were deliberately left uninstalled: everything after this point
runs without them.

---

## 4. A tool leo has never heard of

`vitals` is not one of leo's six. It became a capability by being a file:

```
$ cat .leo/integrations/vitals.sh   # a tool leo has never heard of
#!/usr/bin/env bash
# vitals — codebase hotspots ranked by ROI. MIT, github.com/chopratejas/vitals
vitals_present() { command -v vitals >/dev/null 2>&1; }
vitals_label()   { printf 'Vitals'; }
vitals_hint()    { say "npx --yes skills add chopratejas/vitals"; }
vitals_install() { say "npx --yes skills add chopratejas/vitals"; }
vitals_default() { case "$1" in debugging|review) printf 'on' ;; *) printf 'off' ;; esac; }
vitals_advice()  { say "rank hotspots by ROI before picking what to fix"; }
```

```
$ leo session

leo session
  Mode: debugging

code intelligence
  Serena        ON
  Code graph    ON

efficiency
  RTK           ON
  Headroom      OFF
  Ponytail      OFF
  Caveman       OFF

practice
  TDD           ON

extensions
  Vitals        ON

engineering controls
  Plan          ON   always
  Task IDs      ON   always
  Manifest      ON   always
  Rules         ON   always
  Tests         ON   always
  Human commit  ON   always

dependencies
  Serena        MISSING
      instructions: .leo/tools/serena.md
      uv tool install -p 3.13 serena-agent
      claude mcp add serena -- serena start-mcp-server --context claude-code --project "$(pwd)"
  Code graph    MISSING
      instructions: .leo/tools/graph.md
      curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash
      the installer registers the MCP server with Claude Code itself
  RTK           MISSING
      instructions: .leo/tools/rtk.md
      brew install rtk        (or: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh)
      rtk init -g             installs the auto-rewrite hook
  TDD           installed
      instructions: .leo/tools/tdd.md
      red before green: the test fails first, for the reason you expect
      leo task seeds the to-do with those steps while this is on
  Vitals        MISSING
      npx --yes skills add chopratejas/vitals

warn 4 enabled capability(s) not installed — leo works without them
  install one above, or drop it here: leo session --<name> off
  leo does not install these. Declaring one does not switch anything on.
```

No registry, no `leo plugin add`. It picked up its own label and its own
per-mode default, `leo install vitals` works, and because the file is committed
the capability arrives with a `git clone` rather than in somebody's setup notes.

Note what Vitals does *not* have: an `instructions:` line. Every capability leo
ships with installs a `.leo/tools/<name>.md`, and `leo session` points at it. An
extension can ship one too — drop `.leo/tools/vitals.md` in beside the adapter —
but until it does, leo prints nothing rather than a path to a file that is not
there.

---

## 5. Plan

```
$ leo plan   # after the grilling, filled in
# Plan: Path.to_info_dict drops two fields

Created: 2026-09-04 06:10 UTC

## Goal
`click.Path.to_info_dict()` reports six of its eight declared attributes;
add the two it drops, `executable` and `resolve_path`.

## Non-goals
Every other ParamType's to_info_dict. If they have the same bug it is the same
fix, but each needs its own reading and its own test.

## Wrong-change signal
The omission is deliberate and documented somewhere as part of the API
contract, in which case the fix is a docstring, not a code change.

## Tasks

| #  | Task                                            | Files                | Est LOC | Status  |
|----|-------------------------------------------------|----------------------|---------|---------|
| T1 | add both keys to PathInfoDict and to_info_dict   | src/click/types.py   | 4       | done    |
| T2 | assert every declared attribute round-trips      | tests/test_types.py  | 10      | done    |

Status: pending -> in-progress -> done.
Task IDs must be T1, T2, ... — leo and the manifest match on that format.

## Budget
est: 14 LOC

2 of 2 done
```

Two tasks, four lines and ten. That estimate is what `leo check` measures
against later — and it is about to matter.

---

## 6. Review the diff, hunk by hunk

`leo scan` enumerates; the three judgement columns are the agent's, filled in
from the diff rather than from its memory of what it wrote.

```
$ leo scan
ok   wrote .leo/manifest.md (4 hunks, 34 lines vs est 14)

Now fill in Task / Why / If deleted for every row, from the diff:
  git diff HEAD        <- read this, not your memory of what you wrote
  Never invent a task ID to make a hunk look justified. An honest '-' is
  the entire value of the exercise.
  Then: leo check
```

Four rows, not three. The adapter from step 4 is sitting in the same working
tree, and the diff does not care that it was setup.

---

## 6b. Two things this walkthrough predates

leo gained both of these after the session below was recorded, so they do not
appear in the transcript. They are part of the loop now.

**Subtasks.** A task that turns out to hold more than one decision gets split
rather than guessed at:

```sh
leo task T1 --sub "in-memory store"
```

That adds a `## T1.1` heading **inside** `T1.md` — never a file of its own.
Reading `T1.md` then gives you the parent's reasoning and every child's in one
read, instead of four files to answer one question.

**The grill gate.** Every task and subtask arrives carrying `leo:ungrilled`,
and `leo check` fails while that marker is there:

```
grill
ERR  T1 is ungrilled (2 section(s)) — grill it, record what it settled
  the grill itself: .leo/skills/grilling/SKILL.md
  no limit on questions or rounds — stop on shared understanding
```

It is the only thing in a task file that blocks anything. Everything else
there is a working note. A task nobody questioned is a task built on whatever
the agent assumed, and the assumption becomes code before anyone reads it.

**One more difference you will notice immediately:** `leo check` is quiet when
it passes — three lines, not twenty-six. Every line a passing check prints is
re-read by the agent on every later turn, and a passing check is the least
informative thing leo prints. Use `leo check --verbose` to see each stage. The
failing checks below are still shown in full, because failures stay loud.

> **A note on this transcript.** The session below was run against the real
> `click` repository and the output is what leo printed at the time. The
> `grill` stage was added to leo afterwards, so its lines in the check blocks
> below were inserted by hand to match what the current tool prints — they are
> the only lines here that were not produced by running the command. If you
> follow this walkthrough today and your output differs anywhere else, trust
> your terminal and open an issue.

## 7. Check — three failures, all real

```
$ leo check   # click's real suite, 1990 tests

rules
  no rules yet — write one the next time you fix a real bug

manifest
ok   every hunk reviewed
ok   every task ID is one the plan declared
warn 1 hunk(s), 8 lines, serve no task — revert, promote or split

grill
ok   T1 has been grilled

budget
ERR  est 14 LOC, actual 34 LOC (over 2x) — re-read the request before reviewing

tests
ERR  .venv/bin/python -m pytest -q failed
           )
           def test_parameter(obj, expect):
               out = obj.to_info_dict()
       >       assert out == expect
       E       AssertionError: assert {'exists': Fa...': False, ...} == {'param_type'...y': True, ...}
       E         
       E         Omitting 8 identical items, use -vv to show
       E         Left contains 2 more items:
       E         {'executable': False, 'resolve_path': False}
       E         Use -v to get more diff
       
       tests/test_info_dict.py:214: AssertionError
       =========================== short test summary info ============================
       FAILED tests/test_info_dict.py::test_parameter[Path ParamType] - AssertionErr...
       1 failed, 1990 passed, 25 skipped, 31000 deselected, 1 xfailed in 2.89s

  session mode: debugging
ERR  check failed
```

Worth reading twice, because not one of these is a false alarm:

1. **A hunk serves no task.** The vitals adapter is real work, but it is not
   *this* work. `-` is the honest answer, and the options are revert, promote
   or split.
2. **The budget blew past 2×.** 34 lines against an estimate of 14 — caused by
   the very hunk above. An unrelated file inflating the budget is precisely
   what that check is for.
3. **click's own suite failed.** The fix is correct;
   `test_info_dict.py::test_parameter[Path ParamType]` pinned the exact six-key
   dict, so correcting the dict breaks the test that asserted it was wrong.

---

## 8. Split, and promote

The adapter gets its own commit — it was always a separate change:

```
$ git add .leo/integrations && git commit -m "chore: add the vitals adapter"   # the split
81f2dfe chore: add the vitals adapter
```

The fixture is different. It is genuinely required by this fix, and the plan
never mentioned it. So it does not get folded in quietly: it becomes **T3**,
with a note in the plan recording that the plan missed it.

```
$ leo check   # after the split, and after promoting T3

rules
  no rules yet — write one the next time you fix a real bug

manifest
ok   every hunk reviewed
ok   every task ID is one the plan declared

grill
ok   T2 has been grilled

budget
ok   est 16 LOC / actual 28 LOC

tests
ok   .venv/bin/python -m pytest -q
       ........................................................................ [ 99%]
       .                                                                        [100%]
       1991 passed, 25 skipped, 31000 deselected, 1 xfailed in 2.26s

ok   all checks passed
```

1991 tests: click's 1990, plus the one this change added.

Here is the manifest that came out of it, which is the artefact the whole tool
exists to produce:

```
| # | Hunk | Delta | Task | Why | If deleted |
|---|------|-------|------|-----|------------|
| 1 | `src/click/types.py:1045` | +2/-0 | T1 | PathInfoDict is the declared shape of what to_info_dict returns; adding keys without declaring them leaves the TypedDict wrong | type checkers reject the two new keys as unknown, so the fix does not type-check |
| 2 | `src/click/types.py:1131` | +2/-0 | T1 | the two attributes the method never reported, in the order they are declared on the class | to_info_dict keeps reporting six of eight attributes, which is the bug |
| 3 | `tests/test_info_dict.py:173` | +2/-0 | T3 | this fixture pinned the exact six-key dict, so it fails the moment the dict is correct | click's own suite fails and the fix cannot land |
| 4 | `tests/test_types.py:333` | +22/-0 | T2 | asserts every declared attribute round-trips, not just the two that were missing, so the next attribute added to Path fails here rather than shipping | the fix has no test, and the same omission returns the next time an attribute is added |

Budget: est 16 LOC / actual 28 LOC
```

`Why` is why *that task* requires this hunk, not what the code does. `If
deleted` is the necessity test. At 28 lines this looks like ceremony — the
point is that it reads exactly the same at 500, which is where it stops being
optional.

---

## 9. Where the change stands

```
$ leo session --report

leo session report
  Change        Path.to_info_dict drops two fields
  Mode          debugging
  Declared      serena, graph, rtk, vitals
  Not installed serena, graph, rtk, vitals
  Tasks         3 of 3 done
  Change size   3 file(s), 28 lines
  Manifest      4 hunk(s), 4 reviewed, 0 serving no task
  Tests         `.venv/bin/python -m pytest -q` -- passed, 2026-09-04 05:08 UTC
  Approval      PENDING — leo commit is yours

  no token figures here on purpose: the tools above measure different
  things over overlapping buffers, and summing them would be fiction.
```

`Approval: PENDING` is the only status leo will ever print for a change it can
see. There is no token or savings figure, and there will not be — the tools
named above measure different things over overlapping buffers, and adding those
numbers produces one that is false.

---

## 10. The agent stops

```
$ leo commit "types: report every Path attribute in to_info_dict"   # as an agent
ERR  leo commit needs a human at a terminal

If you are an agent: do not commit. Show the developer what you would run,
and stop there. They decide when the change is done.

If you are a human whose shell has no tty (a script, CI): LEO_YES=1 leo commit ...
exit=2
```

---

## 11. The developer commits

```
$ leo commit "types: report every Path attribute in to_info_dict"   # the developer

rules
  no rules yet — write one the next time you fix a real bug

manifest
ok   every hunk reviewed
ok   every task ID is one the plan declared

grill
ok   T2 has been grilled

budget
ok   est 16 LOC / actual 28 LOC

tests
ok   .venv/bin/python -m pytest -q
       ........................................................................ [ 99%]
       .                                                                        [100%]
       1991 passed, 25 skipped, 31000 deselected, 1 xfailed in 2.27s

ok   all checks passed
[main ba58810] types: report every Path attribute in to_info_dict
 3 files changed, 28 insertions(+)
ok   committed ba58810
  read it back: git show --stat HEAD
```

---

## 12. The record, from git alone

Six months from now `git blame` lands on one of these lines, `git show` answers,
and no AI is involved: which task it served, why that task needed it, what
breaks without it, that 1991 tests passed, and that the agent was working in
`debugging` mode — with nothing compressing what it could see.

```
$ git show --stat HEAD
types: report every Path attribute in to_info_dict

Goal: `click.Path.to_info_dict()` reports six of its eight declared attributes;

| # | Hunk | Delta | Task | Why | If deleted |
|---|------|-------|------|-----|------------|
| 1 | `src/click/types.py:1045` | +2/-0 | T1 | PathInfoDict is the declared shape of what to_info_dict returns; adding keys without declaring them leaves the TypedDict wrong | type checkers reject the two new keys as unknown, so the fix does not type-check |
| 2 | `src/click/types.py:1131` | +2/-0 | T1 | the two attributes the method never reported, in the order they are declared on the class | to_info_dict keeps reporting six of eight attributes, which is the bug |
| 3 | `tests/test_info_dict.py:173` | +2/-0 | T3 | this fixture pinned the exact six-key dict, so it fails the moment the dict is correct | click's own suite fails and the fix cannot land |
| 4 | `tests/test_types.py:333` | +22/-0 | T2 | asserts every declared attribute round-trips, not just the two that were missing, so the next attribute added to Path fails here rather than shipping | the fix has no test, and the same omission returns the next time an attribute is added |

Budget: est 16 LOC / actual 28 LOC
Tests: `.venv/bin/python -m pytest -q` -- passed, 2026-09-04 05:09 UTC

Session: debugging
Assisted-by: Claude Code


 src/click/types.py      |  4 ++++
 tests/test_info_dict.py |  2 ++
 tests/test_types.py     | 22 ++++++++++++++++++++++
 3 files changed, 28 insertions(+)
```

---

## Reproducing this

```sh
mkdir click && gh api repos/pallets/click/tarball/main | tar xz --strip-components=1 -C click
cd click && git init -q .
printf '.venv/\n__pycache__/\n' > .gitignore
python3 -m venv .venv && .venv/bin/pip install -q -e . pytest
git add -A && git commit -qm "click, as published"

leo init
echo 'TEST_CMD=".venv/bin/python -m pytest -q"' >> .leo/config
leo session --mode debugging
```

The defect is in `Path.to_info_dict` in `src/click/types.py`. Gitignore
`.venv/` and `__pycache__/` before adopting leo, or the build output lands in
your manifest and inflates your budget — the same trap step 7 fell into with
one 8-line file.
