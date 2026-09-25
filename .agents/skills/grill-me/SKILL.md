---
name: grill-me
description: A relentless interview to sharpen a plan or design. Use before every task and every subtask.
disable-model-invocation: true
---

Read `.agents/skills/grilling/SKILL.md` and follow it exactly. Invent nothing.

That file is the definition of a grill. It is **not leo's** -- it is Matt
Pocock's, copied byte-for-byte from github.com/mattpocock/skills under the
MIT licence in `.agents/skills/LICENSE`, and vendored rather than referenced
so it cannot drift between two sessions.

This file is adapted from his under the same licence: his says to call Claude
Code's Skill tool, and this names the path instead so any runtime can follow
it.

If your runtime has a skill mechanism of its own, this entry is what it
invokes and the line above is all it needs to do. If it does not, the path
is still the answer: open the file and follow it.
