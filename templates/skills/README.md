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

Claude Code reads skills from `.claude/skills/`. To make `/grill-me` available
there:

```sh
mkdir -p .claude/skills
ln -s ../../.leo/skills/grilling .claude/skills/grilling
ln -s ../../.leo/skills/grill-me .claude/skills/grill-me
```

Other agents read `.leo/workflow.md`, which carries the same instruction in
prose, so the grill still happens without the symlink.
