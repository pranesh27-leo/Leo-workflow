#!/usr/bin/env bash
# desc: write or show the plan — what this change is allowed to be
# usage: leo plan                    show the plan in flight
#        leo plan "<name>"           start the NEXT plan and switch to it
#        leo plan "<name>" --force    replace the plan in flight instead
#        leo plan --list             every plan in this repository
#        leo plan --switch P1        work on an earlier plan again
#
# The plan is the yardstick. Without one, "did the AI do what I asked?" has no
# answer, and `leo check` has no budget to measure against.
#
# There is more than one of them, because a repository outlives a change. The
# developer finishes P1, comes back on Thursday wanting something else, and
# that something else is not an amendment to last week's plan -- it is P2, with
# its own goal, its own non-goals and its own budget. Saying so out loud is the
# difference between a second change and scope creep on the first.
#
# Task ids keep counting across plans. P1 owns T1..T3 and P2 starts at T4. See
# the plan registry in core/lib.sh for why that matters more than it looks.

need_repo

_name=""; _force=0; _list=0; _switch=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force)  _force=1; shift ;;
    --list)   _list=1; shift ;;
    --switch) shift; [ $# -gt 0 ] || die "--switch needs a plan id (leo plan --list)"
              _switch="$1"; shift ;;
    -*)       die "unknown option: $1" ;;
    *)        _name="$1"; shift ;;
  esac
done

# --- list -----------------------------------------------------------------
if [ "$_list" -eq 1 ]; then
  head_ "leo plan --list"
  _cur=$(plan_id)
  _n=0
  for _p in $(plans_list); do
    _n=$((_n + 1))
    _f=$(plan_path "$_p")
    _mark=" "; [ "$_p" = "$_cur" ] && _mark="*"
    _title=$(sed -n 's/^# Plan: *//p' "$_f" | head -1)
    _tasks=$(plan_file_tasks "$_f" | wc -l | tr -d ' ')
    _done=$(awk -F'|' '
      /^\| *T[0-9]/ { st = $6; gsub(/[ \t]/, "", st); if (st == "done") n++ }
      END { print n + 0 }' "$_f")
    _later=$(awk -F'|' '
      /^\| *T[0-9]/ { st = $6; gsub(/[ \t]/, "", st); if (st == "later") n++ }
      END { print n + 0 }' "$_f")
    printf '  %s %-5s %s/%s done%s  %s\n' \
      "$_mark" "$_p" "$_done" "$_tasks" \
      "$([ "$_later" -gt 0 ] && printf ', %s later' "$_later")" \
      "$_title" >&2
  done
  # The single-plan repository. It has no id of its own because every leo
  # before this one only ever had the one, and renaming it on sight would move
  # a file out from under whoever is mid-change in it.
  if [ -f "$LEO_DIR/plan.md" ]; then
    _n=$((_n + 1))
    _mark=" "
    case "$_cur" in ""|legacy) _mark="*" ;; esac
    printf '  %s %-5s %s\n' "$_mark" "legacy" \
      "$(sed -n 's/^# Plan: *//p' "$LEO_DIR/plan.md" | head -1)" >&2
  fi
  [ "$_n" -eq 0 ] && { warn "no plans yet — start one: leo plan \"<name>\""; exit 0; }
  echo >&2
  dim "  * is the plan in flight.  leo plan --switch P1  to move."
  exit 0
fi

# --- switch ---------------------------------------------------------------
if [ -n "$_switch" ]; then
  if [ "$_switch" = "legacy" ]; then
    [ -f "$LEO_DIR/plan.md" ] || die "no legacy plan in this repository"
    rm -f "$CURRENT"
    plan_use legacy
    ok "switched to the legacy plan (.leo/plan.md)"
    exit 0
  fi
  [ -f "$(plan_path "$_switch")" ] \
    || die "no such plan: $_switch  (leo plan --list)"
  mkdir -p "$LEO_DIR"
  printf '%s\n' "$_switch" > "$CURRENT"
  plan_use "$_switch"
  ok "switched to $_switch"
  # The manifest belongs to a cycle, and a cycle belongs to one plan. Carrying
  # one across a switch would let hunks built for P1 be justified by task ids
  # from P2 -- which is the one dishonest move the manifest exists to stop.
  [ -f "$MANIFEST" ] && warn "a manifest from the previous plan is still open — rm .leo/manifest.md && leo scan"
  dim "  $(plan_status)"
  exit 0
fi

# --- show -----------------------------------------------------------------
if [ -z "$_name" ]; then
  [ -f "$PLAN" ] || { warn "no plan yet — start one: leo plan \"<name>\""; exit 0; }
  cat "$PLAN"

  # Where the work stands, so picking up a half-finished change after a day, a
  # reboot or a lost session is one command rather than an archaeology exercise.
  _st=$(plan_status)
  [ -n "$_st" ] && printf '\n%s\n' "$_st" >&2
  _l=$(plan_later)
  [ -n "$_l" ] && dim "  later: $_l   (leo resume <id> to pick one back up)"
  exit 0
fi

# --- create ---------------------------------------------------------------
# --force replaces the plan in flight; without it, a name always starts the
# next plan. That is the reverse of the old behaviour, which refused, and the
# reversal is the feature: "leo plan" with a new name now means "I want
# something else", and wanting something else is the normal case.
if [ "$_force" -eq 1 ]; then
  [ -f "$PLAN" ] || die "nothing to replace — drop --force to start a plan"
  _target="$PLAN"
  _id=$(plan_id)
  _first=$(plan_file_tasks "$PLAN" | head -1)
  _first=${_first#T}
  case "$_first" in ''|*[!0-9]*) _first=$(task_next_n) ;; esac
else
  _id=$(plan_next_id)
  _target=$(plan_path "$_id")
  _first=$(task_next_n)
fi
_second=$(( _first + 1 ))

mkdir -p "$(dirname "$_target")"
cat > "$_target" <<PLANEOF
# Plan: $_name

Id:      ${_id:-legacy}
Created: $(now)

## Goal
<One sentence: what changes, and why.>

## Non-goals
<What this change explicitly does not touch. This is what stops scope creep.>

## Wrong-change signal
<The one observation that would mean this is the wrong change entirely.>

## Tasks

| #  | Task          | Files   | Est LOC | Status  |
|----|---------------|---------|---------|---------|
| T$_first | <first task>  | <files> | <n>     | pending |
| T$_second | <second task> | <files> | <n>     | pending |

Status: pending -> in-progress -> done.
A task you are not doing yet goes to \`later\`: \`leo defer T$_first "why"\`.
Deferred tasks are skipped, not failed — the loop moves to the next one.
Task IDs must be T1, T2, ... — leo and the manifest match on that format, and
they never restart, so an id names one task in this repository forever.

Then give each row its own file and to-do: \`leo task T$_first\`.

## Later
<!-- \`leo defer\` writes here: one line per deferred task, with its reason.
     Nothing else should. \`leo resume\` takes lines back out. -->

## Budget
est: <n> LOC
PLANEOF

if [ "$_force" -eq 0 ] && [ -n "$_id" ]; then
  mkdir -p "$LEO_DIR"
  printf '%s\n' "$_id" > "$CURRENT"
  plan_use "$_id"
fi

ok "plan created: ${_target#"$ROOT"/}${_id:+  ($_id)}"
dim "  tasks start at T$_first — ids never restart, so T$_first is T$_first for good"
dim "  Fill it in, then have the agent work one task at a time."
