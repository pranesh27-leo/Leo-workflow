# leo

A markdown agent harness. The loop, the skills, and the instructions for
each stage — as files your agent reads, in your repository.

```sh
npx leo-workflow init
```

That is the whole installation. It copies the files and exits. The one thing
that runs afterwards is the evidence hook, which your agent calls at the end of
each reply; nothing else watches, and there is nothing to keep installed.

## What you get

| file | what it is |
|---|---|
| `AGENTS.md` | the one file every agent loads |
| `.agents/leo.md` | every stage: the git command that shows the truth, and the file you write |
| `.agents/skills/grill-me/` | interview before building — *Matt Pocock's, adapted* |
| `.agents/skills/tdd/` | test first, and watch it fail |
| `.agents/skills/ponytail/` | what you build — *vendored, MIT* |
| `.agents/skills/humanizer/` | how prose reads — *vendored, MIT* |
| `.agents/skills/feynman/` | explaining what you do not understand, the way Feynman taught |
| `.agents/skills/evidence/` | answers about code from the code, cited, never guessed — **every reply** |
| `.agents/skills/replan/` | change the plan mid-way: stop, show, agree, log |
| `.agents/skills/points/` | the one reply style: 1–5 points, two lines each, Feynman + STE + humanizer in short form — **every reply** |
| `.agents/skills/asd-ste100/` | plain, single-meaning English, inside `points`; strict for text a program parses — *vendored, MIT* |
| `.agents/tools/understand.md` | Understand Anything — a knowledge graph to find where to look |
| `.agents/hooks/check-evidence.js` | the gate behind `evidence`, for Claude Code and Codex |
| `.claude/settings.json` · `.codex/hooks.json` | the hook, registered where each agent reads it |
| `.agents/tools/graph.md` | code graph — call chains, blast radius |
| `.agents/tools/rtk.md` | terminal output reduction |
| `.agents/templates/` | goal, plan, task, manifest, review — copied when a stage needs one |
| `CONTEXT.md` · `ARCHITECTURE.md` · `RULES.md` | the repository's own documents, to fill in |
| `.claude/skills/*/` | the same nine skills, where Claude Code reads them |

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

The tools work the same way. "Check the code graph for this" is not an
instruction you should have to give: the mode says the graph is ON, so the
agent runs `detect_changes` before writing the manifest and `trace_path`
before reading a bug, because those moments are written beside the stages
that want them. A tool that is not installed is reported **once** and then
worked around, not announced every reply.

Every reply opens with one status line: the mode, the stage, and only what
is not the default, such as a skill used on request or a tool it ran
(`[coding · build · graph]`). The always-on skills are not listed every time.

Then the reply itself is **points**: 1–5 of them, each at most two lines. A
point says what happens before it names it (Feynman), in short active
sentences that keep every hedge (STE), with no openers, closers or filler
(humanizer). Ask it to explain or elaborate and you get the long form; the
next reply is points again.

## Answers from the code, not from a guess

Ask an agent how something in your repository works and it will often read
three files, write a confident explanation, and be wrong. Challenge one line
and it looks properly, then says *"Sorry, I was wrong."* The capability was
there. Nothing made it look before answering.

Two layers stop that, on every reply, in every mode:

| layer | what it does | can it be skipped? |
|---|---|---|
| `evidence` skill, in `AGENTS.md` | read before answering, trace the real path, cite `path:LINE` beside every claim, label it verified / inferred / unknown, try to refute it first | yes, it is advice the model follows |
| the Stop hook | before a reply reaches you, checks every cited file exists and every cited line is inside it, and that a reply naming a repo file cites a line. Fails, and the reply goes back to the agent | no, the agent runtime runs it |

The hook cannot tell whether a claim is *true*. It guarantees the evidence a
claim points at is *real*, which a made-up explanation is not. It gives up
after two blocks in a row on one session, so it cannot loop.

A Stop hook runs **after** the reply is on your screen, so a blocked reply
stays visible. The hook tells the agent to send only the corrected points,
not the reply again, and the `evidence` skill tells it to cite every file it
names before it finishes, so the block is rare. Paths are found the ways
agents write them: relative to the session directory or the repository
root, into a sibling directory (`../other/x.py`), absolute, with Windows
backslashes, or relative to a subproject below the session directory.

Claude Code reads `.claude/settings.json`. Codex reads `.codex/hooks.json`,
and asks you to trust it once with `/hooks`. If either file already existed,
`leo init` keeps yours and tells you to copy the hook in from
`.agents/hooks/`.

## The loop

Ask for work and the agent first asks: **"Create a goal for this?"** Say no
and it just does the work. Say yes and it runs the loop:

```
goal -> understand -> grill -> plan -> task -> subtask -> test -> build -> manifest -> review -> commit
```

With `TDD: no`, `test` comes after `build`. Every other stage is the same.

1. **goal**: your words, plus the observable result that means it is met.
2. **understand**: the agent reads the code the goal touches, and cites what it finds.
3. **grill**: it asks about every open decision and every unknown. Any wrapper, helper or new abstraction is put to you, and you decide.
4. **plan, task, subtask**: a goal can have several plans (phases), each with its own tasks.
5. **build**: one line before each task (`▶ Working on`), two after (`✓ Done` and `Noted`).
6. **review**: each Done when is checked against the result, with evidence. It ends with "Is this the result you wanted?"
7. **commit**: drafted only after your yes, the **green signal**. You run it.

Want to change the plan mid-way? Say so at any stage. The agent stops,
shows where every task stands, changes the plan with you, and logs the
change (`replan`). It never guesses: when it does not know, it stops and
asks. Everything lives in `.agents/goals/G1/`, and `.agents/leo.md` defines
each stage.

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

Three, all optional. The code graph and rtk are self-contained binaries on
macOS, Linux and Windows. Understand Anything is an agent plugin. Missing one
is not an error.

| | what it does | install |
|---|---|---|
| [code graph](https://github.com/DeusData/codebase-memory-mcp) | who calls what, what a diff touches | one-line script, no runtime |
| [rtk](https://github.com/rtk-ai/rtk) | filters shell output structurally | `brew install rtk` · `winget install rtk-ai.rtk` |
| [Understand Anything](https://github.com/Egonex-AI/Understand-Anything) | a knowledge graph of the repository, to ask where to look | `/plugin install understand-anything` · see `.agents/tools/understand.md` |

The agent is told never to install them — it shows you the command.

## Licence

MIT.

Four of the nine skills are other people's work. Each is vendored rather
than referenced — a stage whose definition lives on someone else's default
branch can change under you between two sessions — and each ships the licence
it is used under, in its own directory.

| skill | whose | terms |
|---|---|---|
| `ponytail` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | MIT, byte-for-byte |
| `humanizer` | [blader/humanizer](https://github.com/blader/humanizer) | MIT, byte-for-byte |
| `asd-ste100` | [danyuchn/asd-ste100-skill](https://github.com/danyuchn/asd-ste100-skill) | MIT, byte-for-byte, with its rules, examples and linter |
| `grill-me` | [mattpocock/skills](https://github.com/mattpocock/skills) | MIT, **adapted** |

`grill-me` is adapted rather than copied and says so in the file. Upstream is
two files, one of which only says "call the Skill tool with grilling" — an
instruction exactly one runtime can follow. They are one file here, named for
the trigger, so any runtime can read it. The interview method is his,
unchanged.

`tdd`, `feynman`, `evidence`, `points` and `replan` are leo's own. `feynman` quotes Feynman only
where the source is verified, and names the quotes commonly misattributed to him.
