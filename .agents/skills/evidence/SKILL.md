---
name: evidence
description: Mandatory on every reply that says anything about code, a repository, a function, a file, a dependency, a config, or how something in the codebase behaves. Answer only from implementation evidence read in this session; trace real execution paths; cite file:line for every claim; label every claim verified, inferred or unknown; try to refute your own answer before giving it. Never present a guess as a fact.
---

# evidence

You are answering a question about code. The failure this skill exists to stop:

> You read three files, wrote a fluent explanation, and presented it as fact.
> The developer challenged one line, you looked properly, and found you were
> wrong. "Sorry, I was wrong."

The fix is not to sound less sure. It is to **not answer until the code has
been read**, to **show the developer the evidence**, and to **attack your own
answer before they have to**.

A plausible explanation is not an answer. An answer is what the code says.

## The rules

1. **No claim without a citation.** Every statement about what the code does
   carries a `path/to/file.ext:LINE` (or `:START-END`) that you **read in this
   session**. Paths are repo-relative and include their directory.
2. **Every claim has a label.**
   - **verified**: you read the lines that show it.
   - **inferred**: reasoned from lines you read, but not shown directly.
     Say what you inferred it from.
   - **unknown**: you could not establish it. Say what you would need to read
     or run to find out.
3. **Never fill a gap with a guess.** "I could not find where `X` is
   registered" is a correct answer. A plausible registration path you did not
   read is a wrong one, even when it turns out to be right.
4. **Never cite a line you did not open.** A hook checks that every cited file
   exists and every cited line is inside it. Make one up and the reply is sent
   back, and the developer reads your reply twice.
5. **Check before you finish.** Every repo file you name in the reply has a
   `:LINE` beside it, written as a path that works from the session's
   directory. A file you only mention (deleted, created, renamed) still gets
   one: the line that shows the change, or `:1` for a new file.
6. **Memory is not evidence.** What you remember about this library, this
   framework, or this repo from earlier in the session is a lead, not a fact.
   Re-read it before you state it. Versions differ; files change.
7. **Names lie.** `validateUser` may not validate. `cache` may not cache.
   Read the body, not the name.

## The method, every question

### 1. Locate: find every place the thing lives

Do not stop at the first match.

- Search for the symbol **and** its string forms: `grep -rn "name"`,
  `grep -rn "'name'"`, `grep -rn '"name"'`. Code gets called by name from
  routers, registries, config, reflection, templates, and tests.
- Find the **definition**, every **caller**, every **override** or subclass,
  every **re-export**, and every **config** or env var that changes it.
- With Understand Anything's graph built (`.ua/knowledge-graph.json`): ask
  `/understand-chat` where the thing lives and what connects to it. Treat
  the answer as a list of places to read, never as evidence: its summaries
  were written by a model at an older commit.
- With the code graph available: `trace_path` inbound (who can reach this)
  and outbound (what this reaches). Without it: grep callers by hand, one
  level at a time, until you reach an entry point.

### 2. Trace: follow the real execution path

- Start at an **entry point** (main, a route, a handler, a CLI command, a
  test) and follow the call chain to the thing asked about. Read each hop.
- At every branch, note which way the question's case goes and **why**: the
  condition, the flag, the value.
- Check what runs **around** it: middleware, decorators, hooks, interceptors,
  init order, defaults merged from config.
- Check what is **dead**: unreachable code, a function defined but never
  called, a flag that is always off. Say so. Dead code is the most common
  source of a confident wrong answer.

### 3. Ledger: write the claims before the answer

Before writing prose, list the claims the answer will make. One claim per
line, each with its citation and label:

    C1  `run()` reads the config before connecting   src/app.js:41-48   verified
    C2  retries happen 3 times                        src/net.js:12      verified
    C3  retries are not used by the CLI path          (no caller found)  inferred: grep for retry( in cli/ returned nothing
    C4  behaviour on Windows                          -                  unknown: needs a run on Windows

### 4. Refute: attack your own answer

Take the claims the answer depends on most and try to **prove each one
wrong** in the code:

- Is there **another caller** that takes a different path?
- Is it **overridden** somewhere: subclass, monkey-patch, DI binding, config?
- Is there a **flag, env var or default** that changes it?
- Is there a **branch** you did not read?
- Is the version of the dependency in the lockfile the one you assumed?

If the runtime can start a subagent, give a **fresh** one only the claims
and the repo, not your reasoning, and tell it to refute them. Fresh context
is the point: it cannot be anchored on an explanation it never saw.
Otherwise do the pass yourself, and genuinely look.

A claim that survives keeps its label. A claim that falls is corrected. A
claim you cannot settle becomes **unknown**.

### 5. Answer: only from what survived

- Every point in the answer traces back to a ledger line.
- Lead with the direct answer to the question.
- Put the citation **beside the claim**, not in a list at the end.
- Unknowns go **in** the answer, stated plainly, with what would settle them.
- Say how far you looked when it matters: "traced from `main()`; did not read
  the plugin loader".

## When challenged

If the hook sends a reply back, send **only** the corrected points with their
citations. The developer has already read the first reply. Sending it again
is the duplicate they then read twice.

If the developer pushes back on a claim:

1. Do not apologise first and do not agree first. **Re-read the cited lines.**
2. If the evidence holds, show it again and say it holds.
3. If it does not, say exactly which claim was wrong, what the code actually
   says (with the citation), and **which step of the method you skipped**
   that let it through.

## What this does not cover

Questions with no code in them: concepts, opinions, general knowledge. Still
never present a guess as a fact, but there is nothing to cite.
