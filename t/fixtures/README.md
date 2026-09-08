# Benchmark fixtures

Real changes from this repository's own history, not invented ones. Each
directory is one commit:

| Fixture | Commit    | The change                                     |
|---------|-----------|------------------------------------------------|
| small   | `15799a9` | docs: add a beginner walkthrough               |
| medium  | `7e1e411` | flow: task files, per-task to-dos, TDD         |
| large   | `095fa54` | tools: one instruction file per capability     |

Each holds five files, and each pair is one comparison:

    diff.txt          what git shows you for the whole change
    manifest.md       what `leo scan` has you read instead

    taskcontext.txt   the full contents of the files one task names
    task.md           the task file for that task

`manifest.md` was produced by running the real `leo scan` in a worktree at
that commit, not written by hand. `task.md` is a real task file from the
change. `diff.txt` and `taskcontext.txt` come straight out of git.

`context.txt` is the whole change's files and is kept for reference. It is
deliberately **not** what the task comparison uses: the task file covers one
task, so comparing it against every file in the change would flatter leo by
however many tasks the change had.

## They are generated, not committed

    bash t/fixtures/generate.sh

Every byte is derived from commits already in this repository, so committing
them would add ~12,000 lines and half a megabyte to a tool whose entire source
is 2,600 lines — to store what git can reproduce exactly. Only this README and
`generate.sh` are tracked.

The three commits are pinned in `generate.sh`. Change them only if you can say
why the old numbers no longer apply: a benchmark whose inputs move whenever the
result is disappointing measures nothing.
