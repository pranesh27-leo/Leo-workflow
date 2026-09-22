# Architecture

<!--
What the system IS, structurally: the parts, what each one is responsible for,
and the seams between them. Read on demand, not on every request — so it can
be as long as it is useful.

Three files split the same question three ways, and the split is deliberate:

  AGENTS.md        how to work here          every request, keep it short
  CONTEXT.md       what this project is      on demand, prose
  ARCHITECTURE.md  how the pieces fit        on demand, structure

The test for whether something belongs here rather than in CONTEXT.md: would
an agent make a wrong-but-plausible *structural* decision without it — put a
file in the wrong layer, reach across a boundary, duplicate something that
already exists one directory over. If yes, it belongs here.
-->

## The parts

| Part | Lives in | Responsible for | Must not |
|---|---|---|---|
| `<name>` | `<path>` | `<the one job>` | `<the thing it must never reach for>` |

## How a request moves through it

<Follow one real request end to end, naming each part it touches in order.
This is the single most useful paragraph in the file: it is what tells an
agent where a change belongs before it has read anything.>

## Seams

<Where the parts meet, and what crosses. Name the contract at each boundary --
a function signature, a table, a wire format -- and say which side owns it.
A seam with no named owner is where two changes collide six months from now.>

## What is load-bearing

<The things that look ordinary and are not. The module three others import,
the migration that cannot be re-run, the timeout that was tuned against a real
incident. Each with the reason, because the reason is what stops someone
"simplifying" it.>

## What we deliberately do not do

<Structural options that were considered and rejected, with why. This is what
stops an agent helpfully rediscovering an architecture you already priced.>
