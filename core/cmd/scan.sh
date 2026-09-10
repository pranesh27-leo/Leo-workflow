#!/usr/bin/env bash
# desc: break the diff into hunks and start the manifest
# usage: leo scan [base]        (default base: HEAD, or the last record)
#
# This is the deterministic half of review. The shell enumerates every hunk;
# the agent (or you) fills in the three judgement columns:
#
#   Task        which planned task this hunk serves, or "-" for none
#   Why         why that task requires this hunk
#   If deleted  what concretely breaks without it -- the necessity test
#
# A hunk that serves no task is scope creep. That is the whole point: 500 lines
# become ~20 rows you can actually read.

need_repo

# The default is HEAD until a cycle has been recorded, and the tree that cycle
# left behind after. Otherwise a second cycle re-enumerates the first one's
# hunks: nothing landed in between, so HEAD is still the start of the change
# rather than the start of this part of it.
_base="${1:-$(record_base)}"
git rev-parse --verify --quiet "$_base" >/dev/null 2>&1 \
  || die "'$_base' is not a valid git revision"

[ -f "$MANIFEST" ] && die "$MANIFEST already exists — finish or delete it first"

_est=$(plan_est)
_actual=$(lines_changed "$_base")

mkdir -p "$LEO_DIR"
{
  echo "# Manifest"
  echo
  # Only worth recording when it is not the obvious one -- this text ends up in
  # the commit message, and noise there costs more than it saves.
  [ "$_base" = "HEAD" ] || { echo "Base: $_base"; echo; }
  echo "| # | Hunk | Delta | Task | Why | If deleted |"
  echo "|---|------|-------|------|-----|------------|"

  _idx=$(base_index "$_base")
  GIT_INDEX_FILE="$_idx" git diff -U0 "$_base" | awk '
    function flush() {
      if (open) { n++; printf "| %d | `%s:%s` | +%d/-%d |  |  |  |\n", n, file, start, add, del }
      open = 0; add = 0; del = 0
    }
    /^diff --git /  { flush(); next }
    /^\+\+\+ b\//   { file = substr($0, 7); next }
    /^--- /         { next }
    /^@@/ {
      flush()
      s = $0; sub(/^@@ [^+]*\+/, "", s); split(s, a, " "); split(a[1], b, ",")
      start = b[1]; open = 1; next
    }
    open && /^\+/ { add++ }
    open && /^-/  { del++ }
    END { flush() }
  '

  # A new file is one row: git has no hunks to split it by, so the reviewer
  # reads the file. Binaries get a row too, but no line count to pretend with.
  GIT_INDEX_FILE="$_idx" untracked | while IFS= read -r f; do
    if is_text "$f"; then
      printf '| NEW | `%s` | +%s |  |  |  |\n' "$f" "$(wc -l <"$f" 2>/dev/null | tr -d ' ')"
    else
      printf '| NEW | `%s` | binary |  |  |  |\n' "$f"
    fi
  done

  rm -f "$_idx"

  echo
  echo "Budget: est ${_est:-?} LOC / actual ${_actual} LOC"
  echo "Tests: <command> -- <paste the real output>"
} > "$MANIFEST"

_hunks=$(( $(grep -c '^| ' "$MANIFEST" || true) - 1 ))
if [ "$_hunks" -le 0 ]; then
  rm -f "$MANIFEST"
  die "nothing has changed since $_base — nothing to review"
fi

ok "wrote .leo/manifest.md ($_hunks hunks, ${_actual} lines vs est ${_est:-?})"
info ""
info "Now fill in Task / Why / If deleted for every row, from the diff:"
dim  "  git diff $_base        <- read this, not your memory of what you wrote"
dim  "  Never invent a task ID to make a hunk look justified. An honest '-' is"
dim  "  the entire value of the exercise."
dim  "  Then: leo check"
