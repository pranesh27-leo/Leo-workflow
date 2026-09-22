#!/usr/bin/env bash
# desc: move a task or subtask to later work, so the loop steps over it
# usage: leo defer T3 "waiting on the vendor's sandbox key"
#        leo defer T3.2 "the retry path needs its own grill first"
#        leo defer --list                 everything deferred in this plan
#
# "later" is a fourth status next to pending, in-progress and done, and it is
# the one the workflow was missing. Before it there were two ways to get past a
# task you could not do yet: mark it done, which is a lie that survives into
# the commit message, or delete it, which loses the fact that it was ever
# planned. Both were common. Both are worse than a word.
#
# A deferred task is skipped by everything that walks the plan looking for the
# next thing to do -- `leo task`, `leo check`'s grill stage, the reminder in
# `leo session --report`. It is not skipped by anything that reports: it shows
# up in the plan, in SESSION.md and in the commit message, with its reason.
# Invisible deferral is just deletion with extra steps.
#
# The reason is required. A deferral without one is indistinguishable from a
# task somebody forgot, and six weeks later nobody can tell which it was.

need_repo

_id=""; _why=""; _list=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list) _list=1; shift ;;
    -*)     die "unknown option: $1" ;;
    *)      if [ -z "$_id" ]; then _id="$1"; else _why="${_why:+$_why }$1"; fi
            shift ;;
  esac
done

[ -f "$PLAN" ] || die "no plan — nothing to defer (leo plan \"<name>\")"

# --- list -----------------------------------------------------------------
if [ "$_list" -eq 1 ]; then
  head_ "later work"
  _n=0
  for _t in $(plan_later); do
    _n=$((_n + 1))
    printf '  %-6s %-28s %s\n' "$_t" "$(plan_task_name "$_t")" \
      "$(plan_later_why "$_t")" >&2
  done
  # Subtasks, which live in their parent's file rather than in the plan table.
  for _t in $(plan_tasks); do
    for _s in $(task_later_subs "$_t"); do
      _n=$((_n + 1))
      printf '  %-6s %s\n' "$_s" "(subtask of $_t)" >&2
    done
  done
  [ "$_n" -eq 0 ] && dim "  nothing deferred"
  echo >&2
  dim "  pick one back up: leo resume <id>"
  exit 0
fi

[ -n "$_id" ] || die 'usage: leo defer <T3|T3.2> "<why>"'
[ -n "$_why" ] || die "a deferral needs a reason — leo defer $_id \"<why>\""

case "$_id" in
  T[0-9]*) ;;
  *) die "ids are T1, T2, T1.2, … — got: $_id" ;;
esac

_tmp=$(mktemp "${TMPDIR:-/tmp}/leo-defer.XXXXXX")
leo_atexit_add 'rm -f "$_tmp"'

# --- a subtask ------------------------------------------------------------
# A dot in the id means a heading inside a task file, not a row in the plan.
case "$_id" in
  *.*)
    _parent="${_id%%.*}"
    _pf=$(task_file "$_parent")
    [ -f "$_pf" ] || die "$_parent has no file — nothing to defer inside it"
    subtask_ids "$_parent" | grep -qx "$_id" \
      || die "$_pf has no subtask $_id  (leo task $_parent)"
    [ "$(subtask_state "$_parent" "$_id")" = "later" ] \
      && die "$_id is already later work"

    # The marker goes directly under the heading, before the ungrilled comment,
    # because that is the order task_ungrilled reads them in: a Status line
    # that arrived after the marker would not cover it, and the check would go
    # on demanding a grill for work that is not happening.
    awk -v want="$_id" -v why="$_why" -v when="$(now)" '
      { print }
      $1 == "##" && $2 == want {
        printf "Status: later — %s  (%s)\n", why, when
      }' "$_pf" > "$_tmp"
    mv "$_tmp" "$_pf"

    ok "$_id is later work"
    dim "  $_why"
    dim "  it is skipped by the grill check and by the to-do — leo resume $_id"
    exit 0 ;;
esac

# --- a task ---------------------------------------------------------------
plan_has_task "$_id" || {
  _own=$(task_owner "$_id")
  [ -n "$_own" ] && die "$_id belongs to $_own, not the plan in flight — leo plan --switch $_own"
  die "$_id is not a task in this plan  (leo task)"
}

_st=$(plan_task_status "$_id")
[ "$_st" = "later" ] && die "$_id is already later work"
[ "$_st" = "done" ]  && die "$_id is already done — deferring it would undo a fact"

# Two edits to one file, in one pass: the status cell, and a line under
# "## Later" carrying the reason. The cell is what every other command reads;
# the line is the only place the why can live, and a status with no why is the
# thing this command exists to prevent.
#
# The section is created when the plan predates it, so a plan written by an
# older leo does not silently drop the reason on the floor.
awk -v want="$_id" -v why="$_why" -v when="$(now)" '
  function cell(v, w,   s) { s = sprintf("%-*s", w, v); return s }
  /^\| *T[0-9]/ {
    id = $2; gsub(/[ \t]/, "", id)
    split($0, f, "|")
    if (id == want) {
      # Rewrite the status cell only, keeping the width so the table still
      # reads as a table. sub() on the whole line would hit the task name if
      # it happened to contain the old status word.
      w = length(f[6]) - 2
      if (w < 1) w = 1
      f[6] = " " cell("later", w) " "
      out = ""
      for (i = 2; i < length(f); i++) out = out "|" f[i]
      print out "|"
      next
    }
  }
  /^## Later/ { seen = 1; print; printf "- %s — %s  (%s)\n", want, why, when; next }
  { print }
  END {
    if (!seen) {
      printf "\n## Later\n- %s — %s  (%s)\n", want, why, when
    }
  }' "$PLAN" > "$_tmp"
mv "$_tmp" "$PLAN"

ok "$_id is later work"
dim "  $_why"
_next=$(task_current)
if [ -n "$_next" ]; then
  dim "  next: $_next $(plan_task_name "$_next")"
else
  dim "  nothing left in this plan but later work — leo plan \"<next change>\""
fi
dim "  pick it back up: leo resume $_id"
