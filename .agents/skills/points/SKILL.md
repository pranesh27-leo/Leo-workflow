---
name: points
description: Mandatory on every reply. Answer in 1 to 5 numbered points, sized to the question, with no preamble, no closing, and no prose padding. Longer, detailed answers only when the developer asks for detail.
---

# points

Every reply is a short numbered list. The developer reads the answer, not an
essay around it.

## The rules

1. **1 to 5 points.** Pick the number from the question, not from how much
   you know:
   - a yes/no or one-fact question → **1 point**
   - "how do I X" → the steps, **2–5 points**
   - "why", "compare", "what are the options" → one point per reason or
     option, **at most 5**
   More than 5 means you have not decided what matters. Merge or cut.
2. **One idea per point.** One or two sentences. If a point needs a third,
   it is two points or it is padding.
3. **The answer first.** Point 1 answers the question. Context, caveats and
   next steps come after, if at all.
4. **No preamble, no closing.** No "Great question", no "Here's what I
   found", no restating the request, no "Let me know if...", no summary of the
   points you just wrote.
5. **Code, commands, tables and citations stay intact.** A code block or a
   small table can sit inside a point when it *is* the answer. Never shorten
   code, output, error text, or bad news to fit.
6. **Plain words.** Short sentences. No filler adjectives.

## When to write more

Only when the developer asks: "explain in detail", "elaborate", "go deeper",
"long answer", "walk me through it", "write it up", or an explicit request for
a document, report or explanation (the `feynman` skill is one). Then use the
length and structure the request needs, and go back to points on the next
reply.

## What does not count against the limit

- The status line(s) `AGENTS.md` asks for at the top of every reply.
- A code block, command, or table inside a point.
- A question back to the developer, when you are blocked and need their
  decision.

## Example

Q: *"Does `leo init` overwrite existing files?"*

1. No. It skips any file that already exists and says `skip` (`bin/leo.js:105-109`).
2. `leo init --force` overwrites them.
