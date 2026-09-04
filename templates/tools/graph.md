# Code graph — call chains and blast radius

**Standing order: always the CLI.**

```sh
codebase-memory-mcp cli <tool> '<json>'
```

Do not call the MCP tools. The wire is broken and returns the same error for
every query, however well formed.

## The failure signature

```
Cannot read properties of undefined (reading 'properties')
```

That means **the MCP wire, never your query.** Do not rewrite the query, do not
simplify it, do not conclude the symbol does not exist. Switch to the CLI and
run the same thing.

## Calling it

Raw JSON is required. The CLI prints `passing raw JSON is deprecated` on every
call — that warning is expected and harmless, and the flag form it recommends
does not reliably work. Keep passing JSON.

`"project"` is a required key, and it is the **indexed path slug**, not the
directory name. Get it from `list_projects` rather than guessing:

```sh
codebase-memory-mcp cli list_projects '{}'
codebase-memory-mcp cli search_graph '{"project":"home-leo-work-atmosic-cloud-backend","name_pattern":".*Shadow.*"}'
```

Output is a text table: `name`, `label`, `lines`, `in` (inbound edges),
`out` (outbound edges).

## Warm it up once

```sh
codebase-memory-mcp daemon start
```

Roughly 2s cold on the first call, ~500ms after. This is using a tool that is
already installed, not installing one — but it is still a subprocess on the
developer's machine, so say that you ran it.

## Which query answers which question

| Question | Tool |
|---|---|
| who reaches the broken thing | `trace_path`, inbound first |
| what shape is this subsystem | `get_architecture` |
| what does this diff actually touch | `detect_changes` |
| where is this symbol | `search_graph` with `name_pattern` |

`detect_changes` maps a git diff to the symbols it affects, which is the
manifest's `If deleted` column asked from the other direction. Read it before
`leo scan`, not after.

## What this is not

Serena answers *where is this symbol and who references it*. This answers
*what breaks if I change it* — callers of callers, routes, the subsystem a file
belongs to. They overlap less than they look like they do; use both.
