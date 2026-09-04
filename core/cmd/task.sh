#!/usr/bin/env bash
# desc: give a plan task its own file and its own to-do
# usage: leo task                 every task, its to-do and its plan status
#        leo task T1              create .leo/tasks/T1.md, or show it
#        leo task T1 --force      replace it
#
# The stage between the plan and the build. The plan says a task exists and
# whether it is done; this says what is left inside it, and survives a session
# ending mid-task -- which is the whole reason it is a file and not a chat.
#
# It has no opinions. It will make a task the plan never listed (and say so),
# it will not reorder anything, and nothing in `leo check` reads it. The moment
# an unticked box can block work it stops being a working note and becomes
# paperwork, and boxes get ticked to get past it.

need_repo

_id=""; _force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) _force=1; shift ;;
    -*)      die "unknown option: $1" ;;
    *)       _id="$1"; shift ;;
  esac
done

# --- list -----------------------------------------------------------------
if [ -z "$_id" ]; then
  [ -f "$PLAN" ] || { warn "no plan yet — start one: leo plan \"<name>\""; exit 0; }
  head_ "leo task"
  _n=0
  # The plan is read for the ids and the statuses; the task files are read for
  # the to-do. Each fact comes from exactly one place.
  for _t in $(plan_tasks); do
    _n=$((_n + 1))
    # ASCII, not an em dash: printf pads %-7s by bytes, and a multibyte
    # character silently shifts every column to its right by two.
    _td=$(task_todo "$_t"); _td="${_td:--}"
    printf '  %-5s %-7s %-12s %s\n' \
      "$_t" "$_td" "$(plan_task_status "$_t")" "$(plan_task_name "$_t")" >&2
  done
  [ "$_n" -eq 0 ] && { warn "the plan lists no tasks yet"; exit 0; }
  echo >&2
  dim "  leo task T1        create it, or show it"
  exit 0
fi

case "$_id" in
  T[0-9]*) ;;
  *) die "task ids are T1, T2, … — got: $_id" ;;
esac

_f=$(task_file "$_id")

# --- show -----------------------------------------------------------------
# Create-or-show rather than a --show flag: one fewer thing to document, and
# the destructive path stays behind --force, as `leo plan` already does.
if [ -f "$_f" ] && [ "$_force" -eq 0 ]; then
  cat "$_f"
  _td=$(task_todo "$_id")
  [ -n "$_td" ] && printf '\n%s done\n' "$_td" >&2
  exit 0
fi

# --- create ---------------------------------------------------------------
plan_has_task "$_id" || warn "$_id is not in the plan — add the row, or fix the id"

# The to-do the file starts with. This is the one visible thing the TDD
# capability does: with it on, the first two steps are red-before-green, and
# with it off the developer's own order applies. `leo check` runs TEST_CMD
# either way -- the capability governs order, never whether tests happen.
if [ "$(cap_state tdd)" = "on" ]; then
  _todo="- [ ] write the test from \"Done when\" above — the spec, not the implementation
- [ ] run it, watch it FAIL, and confirm it failed for the reason you expect
- [ ] implement the smallest thing that makes it pass
- [ ] run it, watch it pass
- [ ] set $_id to done in .leo/plan.md"
else
  _todo="- [ ] <step>
- [ ] <step>"
fi

# Without this the awk below writes an empty file and reports success -- a
# task file with no "Done when" and no to-do, which is worse than no file.
_tpl="$LEO_HOME/templates/task.md"
[ -f "$_tpl" ] || die "missing template: $_tpl"

mkdir -p "$(dirname "$_f")"
# awk rather than sed: the substituted values are task names and file lists
# from the plan, and a / or & in one of them would break a sed replacement in
# a way that silently produces a wrong file.
#
# Every value goes through the environment rather than -v, because awk
# processes escape sequences in a -v assignment. A multi-line to-do is a syntax
# error there, and a file list like `a\b.go` silently became a backspace.
# ENVIRON is taken literally, with no escaping at any level.
LEO_ID="$_id" \
LEO_NAME="$(plan_task_name "$_id")" \
LEO_FILES="$(plan_task_files "$_id")" \
LEO_EST="$(plan_task_est "$_id")" \
LEO_TODO="$_todo" awk '
  # Literal replacement, character by character. gsub is not usable here:
  # it treats & in the REPLACEMENT as the matched text, so a task named
  # "rate limit & retry" came out as "rate limit <NAME> retry", and a
  # backslash in a file list ate the character after it. index/substr has
  # no metacharacters at all.
  function rep(str, from, to,   out, i) {
    while ((i = index(str, from)) > 0) {
      out = out substr(str, 1, i - 1) to
      str = substr(str, i + length(from))
    }
    return out str
  }
  { line = $0
    line = rep(line, "<ID>",    ENVIRON["LEO_ID"])
    line = rep(line, "<NAME>",  ENVIRON["LEO_NAME"])
    line = rep(line, "<FILES>", ENVIRON["LEO_FILES"])
    line = rep(line, "<EST>",   ENVIRON["LEO_EST"])
    if (line == "<TODO>") { print ENVIRON["LEO_TODO"] } else { print line }
  }' "$_tpl" > "$_f"

ok "task created: ${_f#"$ROOT"/}"
dim "  fill in \"Done when\" first — the to-do falls out of it"
