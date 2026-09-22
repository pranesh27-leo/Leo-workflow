#!/usr/bin/env bash
# desc: take a task or subtask back out of later work
# usage: leo resume T3
#        leo resume T3.2
#
# The other half of `leo defer`. It puts the status back to pending, takes the
# line out of the plan's "## Later" section, and says what that means -- which
# for a subtask is usually that it needs grilling again, because it was never
# grilled in the first place.
#
# It refuses on anything that is not deferred. "Resume" on a task that is
# merely pending would look like it worked and change nothing, and the next
# person would spend ten minutes wondering why the status did not move.

need_repo
[ -f "$PLAN" ] || die "no plan — nothing to resume"

_id="${1:-}"
[ -n "$_id" ] || die 'usage: leo resume <T3|T3.2>'
case "$_id" in
  T[0-9]*) ;;
  *) die "ids are T1, T2, T1.2, … — got: $_id" ;;
esac

_tmp=$(mktemp "${TMPDIR:-/tmp}/leo-resume.XXXXXX")
leo_atexit_add 'rm -f "$_tmp"'

# --- a subtask ------------------------------------------------------------
case "$_id" in
  *.*)
    _parent="${_id%%.*}"
    _pf=$(task_file "$_parent")
    [ -f "$_pf" ] || die "$_parent has no file"
    [ "$(subtask_state "$_parent" "$_id")" = "later" ] \
      || die "$_id is not later work — nothing to resume"

    # Drop the Status line, and only inside this subtask's section. A global
    # delete would resume every deferred subtask in the file at once.
    awk -v want="$_id" '
      $1 == "##" { here = ($2 == want) }
      here && /^Status: *later/ { next }
      { print }' "$_pf" > "$_tmp"
    mv "$_tmp" "$_pf"

    ok "$_id is back in the work"
    _un=$(task_ungrilled "$_parent")
    if [ "${_un:-0}" -gt 0 ]; then
      warn "$_id is ungrilled — grill it before you build it"
      dim  "  it was never grilled: a deferred subtask is not grilled on purpose."
      dim  "  .leo/skills/grilling/SKILL.md"
    fi
    exit 0 ;;
esac

# --- a task ---------------------------------------------------------------
plan_has_task "$_id" || {
  _own=$(task_owner "$_id")
  [ -n "$_own" ] && die "$_id belongs to $_own — leo plan --switch $_own"
  die "$_id is not a task in this plan"
}
[ "$(plan_task_status "$_id")" = "later" ] \
  || die "$_id is not later work — nothing to resume"

awk -v want="$_id" '
  /^\| *T[0-9]/ {
    id = $2; gsub(/[ \t]/, "", id)
    if (id == want) {
      split($0, f, "|")
      w = length(f[6]) - 2
      if (w < 1) w = 1
      f[6] = " " sprintf("%-*s", w, "pending") " "
      out = ""
      for (i = 2; i < length(f); i++) out = out "|" f[i]
      print out "|"
      next
    }
  }
  # The reason goes with the deferral. Leaving it behind would make the plan
  # claim a task is still parked while its status says otherwise, and the two
  # would disagree for as long as the plan lives.
  /^- / {
    line = $0; sub(/^- /, "", line)
    id = line; sub(/ .*$/, "", id)
    if (id == want && inlater) next
  }
  /^## Later/ { inlater = 1 }
  /^## / && !/^## Later/ { inlater = 0 }
  { print }' "$PLAN" > "$_tmp"
mv "$_tmp" "$PLAN"

ok "$_id is back in the work — pending"
_cur=$(task_current)
[ "$_cur" = "$_id" ] && dim "  it is the task in flight again: $(next_step)"
exit 0
