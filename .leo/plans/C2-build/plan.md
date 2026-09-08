# Plan: build a single-file leo, vendored into the working repo

Created: 2026-09-08

## Goal
Today you integrate leo by cloning this repo next to your work and running its
`leo` script out of the clone -- so the working repo depends on a directory
that is not in it, at a revision nobody recorded. Add `leo build`, which emits
one self-contained `dist/leo` with every template and adapter embedded. Drop
that one file into the working repo at `.leo/bin/leo`, commit it, and the repo
is self-sufficient and version-pinned.

## Non-goals
- Not a compiled binary. leo is bash and stays bash; "binary" here means one
  file with no siblings, not a Go or Rust rewrite.
- No installer, no package manager, no `curl | sh`. You build it yourself from
  a clone you can read.
- No network at any point in the build.
- No behaviour change. The bundle must do exactly what the source tree does --
  that is the whole property being bought, and T5 is what proves it.
- No minification or stripping of comments. The comments in leo are the
  documentation; a bundle you cannot read is a binary after all.

## Wrong-change signal
The bundle and the source tree disagree about anything a user can observe. If
`leo init` from `dist/leo` produces even one file that differs by one byte
from `leo init` out of the clone, the bundle is a fork rather than a build,
and everything downstream inherits a difference nobody will find until it
matters.

## The five bindings that have to be severed

`$LEO_HOME` is the source tree, and five places reach into it. Each needs a
seam that the bundler can override -- and the seam has to exist in the source
build too, or the two paths diverge by construction.

| Where               | Reaches for                        | Seam                    |
|---------------------|------------------------------------|-------------------------|
| `core/cmd/help.sh`  | `$LEO_HOME/VERSION`                | `leo_version`           |
| `core/cmd/commit.sh`| `bash $LEO_HOME/leo check`         | `$LEO_SELF`             |
| `core/cmd/init.sh`  | `$LEO_HOME/templates/*`            | `tmpl_cat` / `tmpl_has` |
| `core/cmd/task.sh`  | `$LEO_HOME/templates/task.md`      | `tmpl_cat`              |
| `core/lib.sh`       | `$LEO_HOME/core/integrations/*.sh` | `LEO_BUNDLED` guard     |

The adapter loader is the subtle one. It must stop globbing the builtin
directory in a bundle -- the builtins are already defined as functions -- while
still globbing `$ROOT/.leo/integrations` so a repo can add its own. A bundle
that cannot load a repo's own adapters silently drops a capability.

## Tasks

| #  | Task                                                              | Files                                   | Est LOC | Status      |
|----|-------------------------------------------------------------------|-----------------------------------------|---------|-------------|
| T1 | smoke assertions for the bundle, written first and failing         | t/smoke.sh                              | 70      | done        |
| T2 | seams in lib.sh: leo_version, tmpl_cat, tmpl_has, LEO_SELF         | core/lib.sh, leo                        | 55      | done        |
| T3 | move the five call sites onto the seams                            | core/cmd/{help,commit,init,task}.sh     | 25      | done        |
| T4 | `leo build` -- emit dist/leo with templates and adapters embedded  | core/cmd/build.sh                       | 130     | done        |
| T5 | equivalence test: source init and bundle init agree byte for byte  | t/smoke.sh                              | 45      | done        |
| T6 | docs: build it, vendor it, what .leo/bin/leo is                    | GUIDE.md, README.md, templates/workflow.md | 55   | done        |

Status: pending -> in-progress -> done.

## Budget
est: 420 LOC

Rows sum to 380. The last three changes came in 58%, 59% and 23% over, so 420
prices in one miss -- most likely T4, where embedding has to survive template
content that contains its own heredoc terminators.
