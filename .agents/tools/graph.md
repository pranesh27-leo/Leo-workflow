# Code graph — call chains and blast radius

`codebase-memory-mcp`. Indexes a repository into a queryable graph: who calls
what, what a change touches, what the architecture looks like. It answers the
question grep cannot, which is **who reaches this**.

Optional. Missing it is not an error — say so and carry on.

## Install

A self-contained native binary. No runtime, no Docker, no API key. macOS
(Intel and Apple Silicon), Linux (x86_64 and ARM64), Windows (x86_64).

    # macOS / Linux
    curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash

    # Windows: the PowerShell installer from the same repository.
    # SmartScreen warns about unsigned software; that is expected.

**You do not run this.** Show it to the developer and let them decide.

## Use it from the CLI

    codebase-memory-mcp cli <tool> '<json>'

The CLI, not the MCP wire. The three that earn their place:

    trace_path        who reaches this symbol, and what it reaches
    detect_changes    which symbols this diff actually touches
    get_architecture  the shape, before you go looking in it

## When

**Before the manifest.** `detect_changes` maps your diff to the symbols it
touches, which is the same question the manifest asks one row at a time. Run
it and read it before you write the table, not after.

**When debugging, inbound first.** `trace_path` toward the broken thing
answers "what can even get here", which is usually a much smaller set than it
feels like at 2am.

**When learning a codebase**, `get_architecture` for the shape, then
`trace_path` outbound to follow one call all the way down. Reading files in
alphabetical order teaches you the file names.

## What it does not do

It reads. It does not edit, and it does not know why any of this exists —
that is the plan and the grill, and neither is in the graph.
