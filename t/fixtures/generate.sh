#!/usr/bin/env bash
# generate.sh — rebuild the benchmark fixtures from this repo's own history.
#
# The fixtures are derived data: every byte comes from commits that are already
# in this repository. Committing them would add ~12,000 lines and half a
# megabyte to a tool whose entire source is 2,600 lines, to store something git
# can reproduce exactly. So they are generated and gitignored.
#
# Run this before t/bench.sh. It needs no network and no key.
set -eu

ROOT=$(cd -P "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
LEO="$ROOT/leo"

# fixture <name> <sha> <task-id>
fixture() {
  _name=$1; _sha=$2; _task=$3
  _d="t/fixtures/$_name"
  mkdir -p "$_d"

  # What git shows you for the whole change.
  git diff "$_sha~1" "$_sha" > "$_d/diff.txt"

  # Every file the change touched, in full: the context you would load without
  # a manifest to point you at hunks.
  : > "$_d/context.txt"
  for _f in $(git diff --name-only "$_sha~1" "$_sha"); do
    git cat-file -e "$_sha:$_f" 2>/dev/null || continue
    printf '===== %s =====\n' "$_f" >> "$_d/context.txt"
    git show "$_sha:$_f" >> "$_d/context.txt"
    printf '\n' >> "$_d/context.txt"
  done

  # The manifest leo actually produces for that change -- run, not written.
  # A worktree at the parent with the child's files checked in on top puts the
  # change in the working tree, which is the state `leo scan` reads.
  _wt=$(mktemp -d); rm -rf "$_wt"
  git worktree add -q --detach "$_wt" "$_sha~1"
  ( cd "$_wt" && git checkout -q "$_sha" -- . && mkdir -p .leo \
      && NO_COLOR=1 "$LEO" scan >/dev/null 2>&1 \
      && cp .leo/manifest.md "$ROOT/$_d/manifest.md" )
  git worktree remove --force "$_wt" >/dev/null 2>&1

  # The task-level pair. The task file is a real one from that change; the
  # context is exactly the files it names -- not the whole change's files,
  # which would flatter leo by however many tasks the change had.
  # From t/fixtures/tasks/, not .leo/tasks/. The latter is gitignored working
  # state for whatever change is in flight right now; these belong to changes
  # that finished days ago. Reading them from there worked until the next
  # `leo plan` cleared the directory, at which point the benchmark would have
  # quietly lost half its comparison and still exited 0.
  if [ -f "t/fixtures/tasks/$_name.md" ]; then
    cp "t/fixtures/tasks/$_name.md" "$_d/task.md"
    : > "$_d/taskcontext.txt"
    for _f in $(grep '^Files:' "$_d/task.md" | sed 's/^Files: *//' | tr ',' ' '); do
      _f=$(printf '%s' "$_f" | tr -d ' ')
      [ -n "$_f" ] || continue
      case "$_f" in
        */) for _g in $(git ls-tree -r --name-only "$_sha" | grep "^$_f" || true); do
              printf '===== %s =====\n' "$_g" >> "$_d/taskcontext.txt"
              git show "$_sha:$_g" >> "$_d/taskcontext.txt"
              printf '\n' >> "$_d/taskcontext.txt"
            done ;;
        *)  git cat-file -e "$_sha:$_f" 2>/dev/null || continue
            printf '===== %s =====\n' "$_f" >> "$_d/taskcontext.txt"
            git show "$_sha:$_f" >> "$_d/taskcontext.txt"
            printf '\n' >> "$_d/taskcontext.txt" ;;
      esac
    done
  else
    echo "  note: t/fixtures/tasks/$_name.md is missing — $_name gets no task pair" >&2
  fi

  echo "  $_name ($_sha): $(wc -l < "$_d/diff.txt" | tr -d ' ') diff lines"
}

echo "regenerating fixtures from history"
fixture small  15799a9 T7
fixture medium 7e1e411 T2
fixture large  095fa54 T4
echo "done — now: ANTHROPIC_API_KEY=sk-... bash t/bench.sh"
