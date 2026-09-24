#!/usr/bin/env bash
# Differential test: the bash implementation against the Node one.
#
# This exists only while the port is in flight, and it is deleted with the
# bash tree in the final phase. Its job is the one thing a rewrite needs and
# a normal test suite does not give you: proof that the new implementation
# answers exactly what the old one answered, on inputs nobody wrote a test
# for.
#
# Spot-checking by hand found two real mismatches in the first five minutes
# (plan_status's format, plan_later_why's section scoping). Both were
# invented rather than read -- which is the failure mode of porting from
# memory instead of from the source, and the reason this file runs the two
# side by side rather than trusting either.

set -u
LEOHOME=$(cd -P "$(dirname "$0")/.." && pwd)
BASH_LEO="$LEOHOME/leo"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/leo-diff.XXXXXX")
# Normalised, because TMPDIR conventionally ends in a slash and mktemp keeps
# it: the raw path has "T//leo-diff" in it while $PWD does not, and the
# fixture guard below compares the two as strings.
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
export NO_COLOR=1
pass=0; fail=0

same() {
  _label="$1"; _a="$2"; _b="$3"
  if [ "$_a" = "$_b" ]; then
    pass=$((pass + 1)); printf '  ok    %s\n' "$_label"
  else
    fail=$((fail + 1))
    printf '  FAIL  %s\n' "$_label"
    printf '        bash: [%s]\n' "$_a"
    printf '        node: [%s]\n' "$_b"
  fi
}

# ask_bash <plan> <tasks> <plans> <expr> — evaluate a lib.sh expression.
#
# `set +u` and an exported LEO_HOME are both load-bearing. lib.sh is written
# to be sourced by leo, which sets LEO_HOME first and does not run under
# `set -u` at source time; sourcing it from a harness that does means the
# first unbound reference aborts the subshell before a single function is
# defined, and every answer comes back empty. Empty on both sides compares
# equal, so the whole harness passes while testing nothing -- which is
# exactly what it did until this line was fixed.
ask_bash() {
  ( set +u
    LEO_HOME="$LEOHOME"; export LEO_HOME
    . "$LEOHOME/core/lib.sh" >/dev/null 2>&1
    PLAN="$1"; TASKS="$2"; PLANS="$3"; export PLAN TASKS PLANS
    eval "$4" ) 2>/dev/null
}

ask_node() {
  node -e "
    const p = require('$LEOHOME/src/lib/plan.js');
    const PLAN = process.argv[1], TASKS = process.argv[2], PLANS = process.argv[3];
    const out = (function () { $4 })();
    process.stdout.write(out === undefined || out === null ? '' : String(out));
  " "$1" "$2" "$3" 2>/dev/null
}

# ------------------------------------------------------------------ cases --
# Each case builds a plan in a real repository, then asks both sides the same
# questions. The states are the ones that were bugs at some point: a plan
# with nothing done, one with everything deferred, one mid-flight, one whose
# ids do not start at 1.

# Sets $d and leaves the shell IN the new repository. Deliberately not
# `d=$(make_repo x)`: that runs the body in a subshell, the `cd` dies with it,
# and every `leo plan` afterwards runs in the wrong directory -- which makes
# both sides answer "" and every comparison pass for the wrong reason. This
# harness exists to catch disagreements; one that passes vacuously is worse
# than none.
make_repo() {
  d="$TMP/$1"; mkdir -p "$d"
  cd "$d" || { printf 'FATAL: cannot cd to %s\n' "$d" >&2; exit 1; }
  git init -q . && git config user.email t@t && git config user.name t
  leo_here init >/dev/null 2>&1
}

# leo_here — run the bash leo, but only inside a fixture.
#
# The guard lives here, at the point of mutation, rather than in make_repo:
# the bug it exists for put the `cd` in a subshell, so a check inside
# make_repo passes (the subshell's cwd is right) and the parent still runs
# every later command in the wrong directory. That is not hypothetical -- it
# wrote five stray plans into the leo repository itself and clobbered
# .leo/current, and the harness reported 34/34 while doing it, because empty
# compares equal to empty. A test that can mutate the tree it is testing is a
# bug with a blast radius; this makes that impossible rather than unlikely.
leo_here() {
  case "$PWD" in
    "$TMP"/*) ;;
    *) printf 'FATAL: refusing to run leo outside %s (cwd %s)\n' "$TMP" "$PWD" >&2; exit 1 ;;
  esac
  "$BASH_LEO" "$@"
}

probe() {
  _tag="$1"; _plan="$2"; _tasks="$3"; _plans="$4"
  same "$_tag: planName"   "$(ask_bash "$_plan" "$_tasks" "$_plans" 'plan_name')" \
                           "$(ask_node "$_plan" "$_tasks" "$_plans" 'return p.planName(PLAN);')"
  same "$_tag: planStatus" "$(ask_bash "$_plan" "$_tasks" "$_plans" 'plan_status')" \
                           "$(ask_node "$_plan" "$_tasks" "$_plans" 'return p.planStatus(PLAN);')"
  same "$_tag: taskCurrent" "$(ask_bash "$_plan" "$_tasks" "$_plans" 'task_current')" \
                            "$(ask_node "$_plan" "$_tasks" "$_plans" 'return p.taskCurrent(PLAN);')"
  same "$_tag: planLater"  "$(ask_bash "$_plan" "$_tasks" "$_plans" 'plan_later')" \
                           "$(ask_node "$_plan" "$_tasks" "$_plans" 'return p.planLater(PLAN).join(" ");')"
  same "$_tag: planTasks"  "$(ask_bash "$_plan" "$_tasks" "$_plans" 'plan_tasks | tr "\n" " "')" \
                           "$(ask_node "$_plan" "$_tasks" "$_plans" 'return p.planTasks(PLAN).map(x=>x+" ").join("");')"
  same "$_tag: planEst"    "$(ask_bash "$_plan" "$_tasks" "$_plans" 'plan_est')" \
                           "$(ask_node "$_plan" "$_tasks" "$_plans" 'return p.planEst(PLAN);')"
}

printf '\nfresh plan, nothing touched\n'
make_repo fresh
leo_here plan "rate limiting" >/dev/null 2>&1
probe "fresh" "$d/.leo/plans/P1/plan.md" "$d/.leo/plans/P1/tasks" "$d/.leo/plans"

printf '\none deferred, with a reason\n'
make_repo deferred
leo_here plan "second change" >/dev/null 2>&1
leo_here defer T2 "waiting on the vendor key" >/dev/null 2>&1
probe "deferred" "$d/.leo/plans/P1/plan.md" "$d/.leo/plans/P1/tasks" "$d/.leo/plans"
same "deferred: planLaterWhy" \
  "$(ask_bash "$d/.leo/plans/P1/plan.md" x x 'plan_later_why T2')" \
  "$(ask_node "$d/.leo/plans/P1/plan.md" x x 'return p.planLaterWhy(PLAN, "T2");')"

printf '\nmid-flight: one done, one in progress\n'
make_repo midflight
leo_here plan "third change" >/dev/null 2>&1
P="$d/.leo/plans/P1/plan.md"
# Rewrite the two scaffold rows into a real mid-flight state.
awk '
  /^\| T[0-9]+ \| <first task>/  { print "| T1 | first thing | a.js | 20 | done |"; next }
  /^\| T[0-9]+ \| <second task>/ { print "| T2 | second thing | b.js | 30 | in-progress |"; next }
  { print }' "$P" > "$P.new" && mv "$P.new" "$P"
probe "midflight" "$P" "$d/.leo/plans/P1/tasks" "$d/.leo/plans"

printf '\nids that do not start at 1 (second plan)\n'
make_repo secondplan
leo_here plan "first" >/dev/null 2>&1
leo_here plan "second" >/dev/null 2>&1
probe "P2" "$d/.leo/plans/P2/plan.md" "$d/.leo/plans/P2/tasks" "$d/.leo/plans"
same "P2: taskOwner(T1)" \
  "$(ask_bash x x "$d/.leo/plans" 'task_owner T1')" \
  "$(ask_node x x "$d/.leo/plans" 'return p.taskOwner(PLANS, "T1");')"
same "P2: taskNextN" \
  "$(ask_bash x x "$d/.leo/plans" 'task_next_n')" \
  "$(ask_node x x "$d/.leo/plans" 'return p.taskNextN(PLANS, null);')"
same "P2: plansList" \
  "$(ask_bash x x "$d/.leo/plans" 'plans_list | tr "\n" " "')" \
  "$(ask_node x x "$d/.leo/plans" 'return p.plansList(PLANS).map(x=>x+" ").join("");')"

printf '\nno plan at all\n'
make_repo noplan
probe "noplan" "$d/.leo/plan.md" "$d/.leo/tasks" "$d/.leo/plans"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
