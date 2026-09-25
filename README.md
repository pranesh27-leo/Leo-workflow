# leo

A markdown agent harness. The loop, the skills, and the instructions for
each stage — as files your agent reads, in your repository.

```sh
npx leo-workflow init
```

That is the whole installation. It copies thirteen files and exits. Nothing
runs during your work, nothing watches, nothing to keep installed.

## What you get

| file | what it is |
|---|---|
| `AGENTS.md` | the one file every agent loads |
| `.agents/leo.md` | every stage: the git command that shows the truth, and the file you write |
| `.agents/skills/grill-me/` | interview before building — *Matt Pocock's, adapted* |
| `.agents/skills/tdd/` | test first, and watch it fail |
| `.agents/skills/ponytail/` | what you build — *vendored, MIT* |
| `.agents/skills/caveman/` | what you say — cut what was not asked for |
| `.agents/skills/humanizer/` | how prose reads — *vendored, MIT* |
| `.agents/tools/graph.md` | code graph — call chains, blast radius |
| `.agents/tools/rtk.md` | terminal output reduction |
| `.agents/templates/` | plan, task, manifest, review — copied when a stage needs one |
| `CONTEXT.md` · `ARCHITECTURE.md` · `RULES.md` | the repository's own documents, to fill in |
| `.claude/skills/*/` | the same five skills, where Claude Code reads them |

Open `AGENTS.md` and fill in the block at the top:

```
Mode: coding        <- coding | debugging | learning | review | exploration
TDD:  yes           <- yes | no
```

The mode picks which skills apply. `TDD` picks which build stages the agent
follows. Both are yours to set, and the agent is told never to change them.

**You configure this once and then never mention it again.** "Use ponytail
here" is not something you should have to type: the mode says ponytail is ON,
so it is on — this reply, the next one, and the one after that. `AGENTS.md`
is loaded on every request, so what it says is in force on every request, and
each active skill's rule is written there in one line so it applies without
the agent stopping to open anything.

The agent names which skills are in force and which tools it used, in every
reply. A skill you can see being applied is one you can object to; one
applied silently is indistinguishable from one not applied at all.

## The loop

`TDD: yes` — the test comes first, and the agent watches it fail:

```
grill -> plan -> task -> subtask -> test -> build -> manifest -> commit
```

`TDD: no` — the test comes after, and is still not optional:

```
grill -> plan -> task -> subtask -> build -> test -> manifest -> commit
```

Cycle two, in a new session, cannot edit code:

```
brief -> findings -> close
```

Same stages either way; the order *is* the difference. `commit` and `close`
are yours, not the agent's.

Every stage is a **git command that shows the truth** and a **file written
from what it showed** — `git diff` for the manifest, `git show <sha>` for the
review. git reports, the agent decides, and the decision lands where `git
log` will still have it. `.agents/leo.md` is the only description of it.

The stage carrying the weight is **manifest**: one row per hunk, each naming
the task it serves, why it exists, and what breaks if it is deleted. It goes
into the commit message body, so six months later `git blame` → `git show`
answers the question with no AI in the loop and nothing installed.

## Why there is no program

leo was a CLI. `leo scan` turned the diff into a manifest, `leo check`
enforced it, `leo commit` assembled the message. Eight commands, a plan
registry, a capability system, 415 tests.

It was also five consecutive releases of Windows bugs — an impostor `bash`
from a vendor toolchain, the WSL launcher answering to the same name, a
per-file subprocess that turned `leo --version` into a four-minute hang on a
large repository. Every one was the cost of a program running where it was
not native, and none were bugs in the workflow.

The workflow was always the product. The program generated markdown and
checked that markdown existed; an agent can read the instruction and write
the file, which is what it does with every other instruction in the
repository. So the instructions ship and the program does not.

What is lost is enforcement: nothing now fails a build because a hunk has no
row. `.agents/leo.md` makes the agent check itself at the manifest stage and
report honestly, which is weaker than a gate and is the trade. What is kept
is the artefact — the manifest in the commit message — which is the half that
still answers questions in two years.

## Tools

Two, both optional, both self-contained binaries on macOS, Linux and
Windows. Missing one is not an error.

| | what it does | install |
|---|---|---|
| [code graph](https://github.com/DeusData/codebase-memory-mcp) | who calls what, what a diff touches | one-line script, no runtime |
| [rtk](https://github.com/rtk-ai/rtk) | filters shell output structurally | `brew install rtk` · `winget install rtk-ai.rtk` |

The agent is told never to install them — it shows you the command.

## Licence

MIT.

Three of the five skills are other people's work. Each is vendored rather
than referenced — a stage whose definition lives on someone else's default
branch can change under you between two sessions — and each ships the licence
it is used under, in its own directory.

| skill | whose | terms |
|---|---|---|
| `ponytail` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | MIT, byte-for-byte |
| `humanizer` | [blader/humanizer](https://github.com/blader/humanizer) | MIT, byte-for-byte |
| `grill-me` | [mattpocock/skills](https://github.com/mattpocock/skills) | MIT, **adapted** |

`grill-me` is adapted rather than copied and says so in the file. Upstream is
two files, one of which only says "call the Skill tool with grilling" — an
instruction exactly one runtime can follow. They are one file here, named for
the trigger, so any runtime can read it. The interview method is his,
unchanged.

`tdd` and `caveman` are leo's own.
