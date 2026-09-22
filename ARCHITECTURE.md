# Architecture

leo is one bash script that finds its own install, sources a library, and
sources one file per command. There is no framework here and there is not
going to be one: the whole tool is meant to be readable in an afternoon by
somebody who has to trust it with their commit history.

Portability floor: **bash 3.2** (the one macOS ships), POSIX coreutils, git.
No jq, no node, no network, no `sed -i`, no GNU-only flags. Every one of those
is a dependency somebody would have to install before they could review what
leo does, which defeats the point.

## The parts

| Part | Lives in | Responsible for | Must not |
|---|---|---|---|
| entrypoint | `leo` | resolving `LEO_HOME` through symlinks, dispatching one command | know anything about any command |
| library | `core/lib.sh` | every shared fact: repo, plans, tasks, records, reviews, session, tools | run anything the user asked for |
| commands | `core/cmd/<name>.sh` | one verb each | know about each other, except by `$LEO_SELF` |
| adapters | `core/integrations/<name>.sh` | naming one external tool: detect, hint, install, advise | install, launch, wrap or configure anything |
| templates | `templates/` | every file leo writes into a repository | be read directly — go through `tmpl_cat` |
| asset seam | `core/lib.sh`, one block | the only place leo reads its own install | be bypassed, ever |

**There is no registry.** A command is a file in `core/cmd/`; a capability is
a file in `core/integrations/`; a rule is a file in `.leo/rules/`. Adding one
is dropping a file in. That is deliberate, and it is why three of the rules in
`.leo/rules/` exist: with no registry, nothing else notices when a new file is
added and never documented, never installed, or never reachable.

## How a command runs

1. `leo` resolves its own path, following symlinks, and exports `LEO_HOME`
   and `LEO_SELF`. `LEO_SELF` is what a command re-execs when it needs leo
   itself — `leo record` re-runs the checks that way.
2. `core/lib.sh` is sourced. It computes `ROOT`, resolves the **active plan**,
   reads `.leo/config` and `.leo/session`, sources every adapter from leo's own
   directory and then the repository's, builds `CAPS`, and installs the single
   EXIT trap.
3. `core/cmd/<name>.sh` is sourced with the remaining arguments in `$@`.
4. On the way out — success, `die`, `set -e`, or a signal — the one exit
   handler runs the registered cleanups and writes `SESSION.md`.

Step 4 is why `.leo/rules/ONE-EXIT-TRAP.md` exists. `trap ... EXIT` does not
stack, so a command installing its own would silently replace leo's, and the
only symptom would be a status file that quietly stopped being current.

## Seams

**The asset seam.** `leo_version`, `tmpl_has` and `tmpl_cat` are the only
things that read leo's own install. `leo build` emits the same three functions
with the templates compiled in and sets `LEO_BUNDLED`, so a single-file build
answers from itself. Any direct `$LEO_HOME/templates/...` read works perfectly
in a clone and fails only for whoever vendored the bundle — the one place
nobody is looking. `ASSET-SEAM` fails the check on one.

**The adapter contract.** Three required functions (`_present`, `_hint`, and a
name in `BUILTIN_CAPS`) and five optional ones (`_label`, `_advice`, `_kind`,
`_oneline`, `_mcp`, `_install`). `cap_present` collapses an adapter's status to
0 or 1, because `2` is leo's own code for "no adapter" and an adapter can
return it by accident.

**The plan registry.** `PLAN` and `TASKS` are resolved once, in `core/lib.sh`,
from `.leo/current`. No command knows the registry exists; a command that
changes which plan is active calls `plan_use` so the rest of its own run — and
the exit handler — sees the new one.

## What is load-bearing

- **`base_index`.** Every diff leo takes goes through a throwaway git index
  seeded from the base. Using the real index makes the diff correct and the
  repository wrong: an ordinary `git commit` afterwards sweeps the recorded
  change into it. The developer's index is theirs.
- **The `|| true` on every guarded read.** Under `set -e` with `pipefail`, one
  grep that legitimately matches nothing kills the command *after* the value
  was computed. That looks exactly like success to a script and exactly like a
  hang to a person. `t/smoke.sh` exists mostly to catch it.
- **`cap_fingerprint`.** The tools block in `AGENTS.md` is stamped with it.
  It must be computed once per run: an adapter is allowed to detect itself by
  reading `AGENTS.md`, so two calls straddling the write can disagree.
- **Variable names in anything the exit handler calls.** The handler holds a
  temp path across a call into a dozen helpers sharing one flat namespace. A
  two-letter name there is a collision waiting for whichever helper grows a
  loop next; it has already happened once.

## What we deliberately do not do

- **Install, launch, wrap or configure any tool.** `leo install` is the single
  exception, it prints the exact command first, and it refuses without a human
  at a terminal. leo works with none of the tools it can name installed, and
  that property is what makes an optional dependency actually optional.
- **Commit.** `leo record` ends a cycle; `leo commit` lands it and is the
  developer's. An agent may run the first and never the second.
- **Report token savings.** Every tool leo names measures a different thing
  against a different denominator over overlapping buffers. Summing them
  produces a number that is false, and a false number is worse than none.
- **Parse anything that needs a parser.** `.leo/config` and `.leo/session` are
  `KEY=value` shell. The manifest, the plan and the reviews are markdown tables
  read with `awk -F'|'`. If a format here ever needs real parsing, the format
  is wrong.
