# Caveman — compressing your own prose

**Status: skill only.** leo uses the MIT skill and nothing else. There is no
gateway, no account, no `CAVE_API_KEY`, no `CAVE_GATEWAY_URL`, and no
`caveman wrap`. If a skill asks you to configure any of those, stop and tell
the developer instead.

`npx caveman` is not a package and never was — it fails with *"could not
determine executable to run"*. The MIT half is a set of skills; the CLI and
proxy half is the BSL-1.1 cloud gateway, which leo deliberately does not
install. Read `core/integrations/caveman.sh` for the licensing reasoning.

## What it is for

Reducing **output** tokens — your prose, not what you read. Every other
capability on leo's list changes what reaches you; this one changes what you
send back.

## What it must never compress

This list is not advice, and it does not bend for a mode or a request to be
brief:

- The manifest's `Why` and `If deleted` columns. They are the record — the
  reason a line exists, read years later by someone with no session and no AI.
  A compressed `Why` is a lost one.
- A rule violation from `leo check`.
- A failing test, and the output that shows how it failed.
- An error message. Any error message, in full.

Brevity everywhere else is welcome. Not here.

## Skills that work

These fire from prompts and need no gateway:

| Skill | For |
|---|---|
| `caveman` | compressed responses |
| `caveman-commit` | a conventional commit message |
| `caveman-compress` | compressing memory files |
| `caveman-review` | one line per review finding |
| `caveman-stats` | session token usage |
| `caveman-help` | the reference card |
| `caveman-explore` | read-only repository exploration |

## Skills that must not be invoked

These require the cloud gateway leo does not use. Invoking one sends the
developer down a setup path leo has decided against:

`caveman-setup` · `caveman-manage` · `caveman-optimize` ·
`caveman-evidence-review` · `caveman-learn` · `caveman-discover`

## Where it installs

Into the repository, not onto the machine:

```
.agents/skills/caveman*      the skills themselves
.claude/skills/caveman*      symlinks, for Claude Code
skills-lock.json
```

That is why leo detects a directory rather than a binary on `PATH`.

## Install it *between* changes, not during one

The skill bundle is around **69 files and 3,700 lines**, written into the
repository as untracked files. `leo check` counts untracked lines against the
change in flight — correctly, because that is how it catches generated output
nobody asked for — so installing this mid-change reports thousands of lines you
did not write and fails the budget check.

Install it when no change is open, then either commit the skills or add them to
`.gitignore`, before running `leo plan`. Note that the bundle also brings
skills that are not caveman's — `investigate-first`, `safe-refactor`,
`surgical-patch`, `verify-and-stop`, `lean-build`, `migration`, `cavecrew` —
so read what landed before committing it.
