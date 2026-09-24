# Porting leo to Node

## Why

Every Windows fix in 0.7.1–0.7.4 was leo fighting the fact that bash is not
native to Windows:

| Version | What broke | Root cause |
|---|---|---|
| 0.7.0 | `syntax error: bad substitution` | npm picked a BusyBox `bash.exe` from a vendor toolchain |
| 0.7.1 | `/bin/bash: C:/...: No such file` | the guard accepted `System32\bash.exe` — the WSL launcher |
| 0.7.2 | (never published) | excluded WSL by path, still guessing at interpreters |
| 0.7.3 | worked, then hung | npm's shim stopped choosing the interpreter |
| 0.7.4 | multi-minute hang | `grep`+`wc` **per untracked file**; spawns cost ~10x more through MSYS |

None of these are bugs in leo's logic. They are all the cost of running a
POSIX program on a system that emulates POSIX. Node is native on all three
platforms, is already a hard dependency (it is the npm entry point), and
removes the entire class.

The design principle does not change. leo's commit messages have argued all
along that there must be exactly **one** implementation, because two
implementations disagree and then leo passes on one platform what it fails on
another. That still holds — on a runtime that is genuinely one implementation
everywhere, instead of one that is emulated on a third of its installs.

## What the test suite actually is

2,796 lines across four files, and it splits in two:

- **Behavior spec — survives the port unchanged.** 227 invocations of `$LEO`
  as a subprocess (140 smoke, 65 negative, 22 windows), asserting on stdout,
  stderr, exit codes and file contents. This is the real specification and
  the port must satisfy every one of them.
- **Implementation audit — mostly becomes obsolete.** `t/windows.sh` is ~123
  lines of policing bash-specific hazards: CRLF in sourced shell files, GNU-only
  `sed -i`/`readlink -f`, shebang portability, impostor `bash.exe`, the WSL
  launcher, MSYS toolchain presence. When there is no bash, most of this has
  nothing left to check. A handful of genuinely platform-level cases stay
  (reserved Windows filenames, paths with spaces, MAX_PATH, case collisions).

A small number of tests source `core/lib.sh` directly and must be re-pointed
at the JS equivalents: `t/smoke.sh:622` (is_text), `t/smoke.sh:676` (the
batching test), `t/windows.sh:158`.

## Architecture

```
bin/leo.js              the one entry point — dispatch, exit codes, exit trap
src/lib/ui.js           say/info/dim/ok/warn/err/die, colour, NO_COLOR
src/lib/fsx.js          atomic write, KEY=value config w/ CRLF, isText
src/lib/repo.js         git: root, changed, linesChanged, untracked, baseIndex
src/lib/plan.js         plan + task model (the markdown table parser)
src/lib/records.js      leo record's filed cycles
src/lib/review.js       cycle-two state
src/lib/caps.js         capability/adapter system
src/lib/session.js      mode policy, session_desc, SESSION.md generation
src/cmd/*.js            17 commands, one file each — no registry, same as now
src/integrations/*.js   7 adapters, same contract
```

### Decisions

**git stays a subprocess, everything else does not.** `spawnSync('git', [...])`
with an argument array — no shell, so no quoting or word-splitting, and it
invokes `git.exe` directly rather than through an emulation layer. One spawn
per git operation. The per-file `grep`/`wc`/`awk`/`sed` spawns all become
in-process JS, which is where the Windows win actually comes from.

**Atomic writes** stay temp-file-then-rename (`writeFileSync` + `renameSync`),
same as today. Rename within a directory is atomic on NTFS as well as POSIX.

**The exit trap** becomes `process.on('exit')`, which is synchronous-only —
so `sessionDocWrite` must use the sync fs API. `SIGINT`/`SIGTERM` get explicit
handlers that write the document and exit 130/143, matching the bash traps.

**`is_text`** reads the first 8KB and looks for a NUL byte, rather than
spawning `grep -I`. Must keep the current edge cases: an empty file is text,
a file of only blank lines is text, a file with NULs is binary.

**`leo build`** concatenates `src/` into one runnable `.js` with templates
inlined, the same contract as the current bundle: the file is the whole
install and reads nothing next to itself.

**Byte compatibility is the bar.** `.leo/` layout, `plan.md` tables,
`manifest.md`, `SESSION.md`, and the AGENTS.md block splicing must be
byte-identical. A repository initialised by bash-leo must keep working under
node-leo without migration.

## Phases

Each phase is self-contained and ends green.

### Phase 1 — foundation
`bin/leo.js` dispatcher (argv, `--version`, `--help`, unknown-command error,
exit codes 0/1/2), `ui.js`, `fsx.js`, `repo.js`, the exit trap.
**Verify:** `leo --version` and `leo help` byte-match bash-leo. The negative
suite's SESSION.md atomicity and "written on every exit path including
failures" cases pass. `isText` matches the four cases at `t/smoke.sh:622`.

### Phase 2 — plan and task model
`plan.js` (the table parser is the heart: ids, status, estimates, owners,
subtasks, later-work), then `init`, `plan`, `task`, `defer`, `resume`.
**Verify:** the negative suite's plan cases — id continuity across P1/P2,
cross-plan task ownership, one Status line per task, deferral reasons
required, grill sections counted.

### Phase 3 — capabilities and session
`caps.js`, the 7 adapters, `session.js`, then `session`, `use`, `install`,
`agents`.
**Verify:** mode policy, tool ledger, DENIED handling, capability
fingerprint stability, AGENTS.md splicing that does not eat hand-written text.

### Phase 4 — the review pipeline
`scan`, `check` (485 lines, the largest), `record`, `commit`, `review`, `docs`.
**Verify:** the bulk of smoke.sh — budget overshoot, unmapped hunks, invented
task ids, the commit refusal without a human (exit 2), RULES.md round-trip.

### Phase 5 — build
`leo build` emitting a single-file bundle.
**Verify:** the bundle runs standalone from a directory containing nothing else.

### Phase 6 — retire bash
Delete `leo`, `leo.ps1`, `core/`, the POSIX re-exec guard, and the
bash-specific half of `t/windows.sh`. Re-point the three tests that source
`core/lib.sh`. Update README/GUIDE.
**Verify:** full suite green; `npm pack` ships no `.sh`; a real global install
runs on Windows, Ubuntu and macOS.

## Anti-patterns

- **Do not** reimplement from the bash source alone. The tests are the spec;
  when they disagree with the shell, the tests win.
- **Do not** change output text, spacing or exit codes opportunistically. The
  suite asserts on them and so do users' scripts.
- **Do not** add a dependency. Node stdlib only — `package.json` has no
  `dependencies` and should not grow one.
- **Do not** use `shell: true` in `spawnSync`. It reintroduces quoting bugs
  and, on Windows, an interpreter leo does not control.
- **Do not** go async. The exit trap cannot await, and leo is a short-lived
  CLI where sync fs is simpler and fast enough.
