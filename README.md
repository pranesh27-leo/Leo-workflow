# leo

A markdown agent harness. The loop, the skills, and the instructions for
each stage — as files your agent reads, in your repository.

```sh
npx leo-workflow init
```

That is the whole installation. It copies thirteen files and exits. Nothing
runs during your work, nothing watches, nothing to keep installed.

## What you get

```
AGENTS.md                          the one file every agent loads
.agents/leo.md                     every stage, and exactly what to write
.agents/skills/grilling/SKILL.md   how to interview before building
.agents/skills/grill-me/SKILL.md   the trigger
.agents/skills/ponytail/SKILL.md   do not write code that should not exist
.agents/skills/caveman/SKILL.md    say it once, say it short
.agents/tools/graph.md             code graph — call chains, blast radius
.agents/tools/rtk.md               terminal output reduction
.claude/skills/*/                  the same four, where Claude Code reads them
```

Open `AGENTS.md` and fill in the block at the top:

```
Mode: coding        <- coding | debugging | learning | review | exploration
TDD:  yes           <- yes | no
```

The mode picks which skills apply. `TDD` picks which build stages the agent
follows. Both are yours to set, and the agent is told never to change them.

## The loop

```
1  grill -> plan -> task -> subtask -> build -> manifest -> commit
2  brief -> read -> findings -> close
```

Cycle one builds. Cycle two reads a commit in a **new session** and cannot
edit code — a finding is not a fix; the fix is a new cycle one.

What each stage means and exactly what to write is `.agents/leo.md`. That is
the only description of the loop, so there is nothing for it to disagree
with.

The stage that carries the weight is **manifest**: one row per hunk, each
naming the task it serves, why it exists, and what breaks if it is deleted.
It goes into the commit message body, so six months later `git blame` →
`git show` tells you which task a line served, with no AI in the loop and
nothing installed.

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

## Upgrading from 0.x

1.0.0 is a different tool with the same name. If you were using the CLI,
`leo scan`, `leo check`, `leo record`, `leo commit`, `leo review`,
`leo plan`, `leo task` and `leo defer` no longer exist, and neither does
`SESSION.md` or `.leo/`. The last CLI release is tagged `v0.8.2` and stays
installable:

```sh
npm install -g leo-workflow@0.8.2
```

## Licence

MIT.

`grilling` is **not leo's**. It is Matt Pocock's, copied byte-for-byte from
[mattpocock/skills](https://github.com/mattpocock/skills) under the MIT
licence in `.agents/skills/LICENSE`, which is his and travels with the copy.
It is vendored rather than referenced because the grill is the first stage of
the loop, and a stage whose definition lives on someone else's default branch
is a stage that can change under you between two sessions.

`grill-me` is **adapted** from his, under the same licence. His version says
to call Claude Code's Skill tool; this one names the file to read, so a
runtime without that mechanism can follow it too. The change is the pointer
and nothing else.
