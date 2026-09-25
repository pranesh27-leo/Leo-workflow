# Vendored skills

`grill-me` and `grilling` are **not leo's**. They are Matt Pocock's, copied
here unmodified from https://github.com/mattpocock/skills and used under the
MIT licence in `LICENSE`, which is his and travels with the copy.

They are vendored rather than referenced because the grill is the first stage
of leo's loop, and a stage whose definition lives on someone else's default
branch is a stage that can change under you between two sessions.

**Do not edit `grilling/SKILL.md`.** If leo needs the grill to behave
differently, that belongs in `.leo/workflow.md`, which says *when* to grill and
what to do with the answers. This file says *how* to grill, and there is no
reason for leo to hold an opinion about that as well as a copy of it.

Runtimes do not read skills from here. `leo init` installs working copies
where they do:

```
.leo/skills/grilling/SKILL.md      <- canonical, vendored, what you read
.claude/skills/grilling/SKILL.md   <- what Claude Code loads
.agents/skills/grilling/SKILL.md   <- the cross-tool convention
```

All of them live inside the repository, so they apply to work in this repo and
nowhere else — unlike `~/.claude/skills/`, which would follow you into every
project. All of them are tracked in git, so a fresh clone has a working grill
without anyone running anything.

This used to be a manual step described in this file, and the result was
predictable: the skill shipped, nobody wired it up, `/grill-me` did not exist,
and `leo check` failed ungrilled tasks while pointing at a file no runtime had
loaded. The `SKILLS-REACHABLE` rule now fails the build rather than the README
asking nicely.

Two conventions is not the same as all of them, and leo does not pretend
otherwise. A runtime that reads neither path is pointed at `.leo/skills/`,
which is where the canonical copy has always been — `leo session` prints
exactly what was wired, so nobody has to guess.

The grill itself is runtime-agnostic prose. `grill-me` is leo's own trigger
shim and names no vendor's mechanism: it says which file to read, because
"call the Skill tool" is an instruction only one harness can follow.
