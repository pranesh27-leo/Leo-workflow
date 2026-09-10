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

Claude Code reads skills from `.claude/skills/`, **not** from here. `leo init`
installs a working copy there for you:

```
.leo/skills/grilling/SKILL.md      <- canonical, vendored, what you read
.claude/skills/grilling/SKILL.md   <- what Claude Code loads
```

Both live inside the repository, so they apply to work in this repo and nowhere
else — unlike `~/.claude/skills/`, which would follow you into every project.
Both are tracked in git, so a fresh clone has a working grill without anyone
running anything.

This used to be a manual step described in this file, and the result was
predictable: the skill shipped, nobody wired it up, `/grill-me` did not exist,
and `leo check` failed ungrilled tasks while pointing at a file no runtime had
loaded. The `SKILLS-REACHABLE` rule now fails the build rather than the README
asking nicely.

Only Claude Code. Cursor, Codex and Aider each have their own convention, and
leo says which runtime it wired rather than guessing at the others —
`leo session` prints it.
