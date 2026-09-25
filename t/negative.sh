#!/usr/bin/env bash
# Negative tests: every way the new machinery is supposed to REFUSE.
#
# t/smoke.sh proves leo works when it is used correctly. This file proves it
# does not work when it is not -- which is the half that actually matters here,
# because every feature added in this change is a gate, and a gate that opens
# for everyone is a decoration.
#
# One section per feature, and each asks the same three questions:
#
#   does it refuse the wrong input, with a message naming the fix?
#   does it refuse the *plausible* wrong input -- the one somebody would
#     actually type -- rather than only the obviously broken one?
#   after it refuses, is the repository still in a state you can work in?
#
# The third is the one that is easy to skip and expensive to get wrong. A
# command that validates its arguments after it has half-written a file leaves
# a repository that needs manual repair, and no amount of correct error text
# makes up for it.

set -u
LEOHOME=$(cd -P "$(dirname "$0")/.." && pwd)
LEO="$LEOHOME/leo"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/leo-neg.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export NO_COLOR=1
pass=0; fail=0

ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

# refuses <label> <command...> — the command must exit non-zero AND say
# something. A silent refusal is the failure mode this whole suite is shaped
# around: under `set -e` with `pipefail`, one grep that matches nothing kills
# the command mid-run, and that looks exactly like a clean refusal.
refuses() {
  _label="$1"; shift
  _out=$("$@" 2>&1); _rc=$?
  _n=$(printf '%s' "$_out" | grep -c .)
  if [ "$_rc" -eq 0 ]; then
    bad "$_label: expected a refusal, got rc=0"
  elif [ "$_n" -lt 1 ]; then
    bad "$_label: refused silently (rc=$_rc) — nobody can act on that"
  else
    ok "$_label"
  fi
}

# accepts <label> <command...> — the mirror. Several of the refusals below
# would be trivially satisfiable by a command that refuses everything.
accepts() {
  _label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$_label"
  else bad "$_label: expected success, got rc=$?"; fi
}

says() { printf '%s' "$1" | grep -qi "$2" && ok "$3" || bad "$3"; }

# set_status <plan-file> <id> <status> — rewrite one row's status cell.
#
# awk on the pipe fields, not sed on the rendered row. The first version of
# this was `sed 's/| T2 |\(.*\)| pending  |/.../'`, which depends on the exact
# number of padding spaces the plan template happens to emit. It silently
# matched nothing, three later assertions cascaded off a task that was never
# marked done, and the failures pointed at leo rather than at the test.
set_status() {
  awk -v want="$2" -v st="$3" '
    /^\| *T[0-9]/ {
      id = $2; gsub(/[ \t]/, "", id)
      if (id == want) {
        split($0, f, "|")
        w = length(f[6]) - 2; if (w < 1) w = 1
        f[6] = " " sprintf("%-*s", w, st) " "
        out = ""
        for (i = 2; i < length(f); i++) out = out "|" f[i]
        print out "|"; next
      }
    }
    { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# --- a repository to break ------------------------------------------------
mkdir -p "$TMP/repo" && cd "$TMP/repo"
git init -q . && git config user.email t@t && git config user.name t
echo one > f.txt && git add -A && git commit -qm init
"$LEO" init >/dev/null 2>&1
printf 'TEST_CMD="true"\n' >> .leo/config
git add -A && git commit -qm adopt
"$LEO" session --mode coding >/dev/null 2>&1

printf '\nleo defer — refusing what should not be deferred\n'

# No plan at all. The plan is what a status lives in; without one there is
# nothing to set, and writing a plan on the fly would invent a change nobody
# asked for.
refuses "defer with no plan" "$LEO" defer T1 "why"

"$LEO" plan "first change" >/dev/null 2>&1

# The reason is the feature. A deferral with no why is indistinguishable from
# a task somebody forgot about, and six weeks later nobody can tell which it
# was -- which is precisely the confusion this status exists to remove.
refuses "defer with no reason" "$LEO" defer T1
out=$("$LEO" defer T1 2>&1); says "$out" "reason" "the refusal names the reason as the missing part"

refuses "defer with no arguments at all" "$LEO" defer

# An id the plan never declared. Accepting it would write a Later line for a
# task that does not exist, and `leo resume` would then have nothing to undo.
refuses "defer an id the plan does not have" "$LEO" defer T99 "why"

# A malformed id. T-then-digits is the format the manifest matches on, and a
# status row keyed on something else is a row nothing can find again.
refuses "defer a malformed id" "$LEO" defer banana "why"
refuses "defer an id with no number" "$LEO" defer T "why"

accepts "defer a real task" "$LEO" defer T1 "waiting on a key"

# Twice. The second one would append a second Later line for the same task and
# leave the plan claiming one deferral in two places.
refuses "defer the same task twice" "$LEO" defer T1 "again"
n=$(grep -c '^- T1 ' .leo/plans/P1/plan.md || true)
[ "${n:-0}" -eq 1 ] && ok "the refused second deferral wrote nothing" \
                    || bad "the plan has $n Later lines for T1, expected 1"

# Deferring something already finished would turn a fact into a plan.
set_status .leo/plans/P1/plan.md T2 done
[ "$(grep -c '| done' .leo/plans/P1/plan.md)" -eq 1 ] \
  && ok "the fixture marked T2 done" || bad "the fixture did not mark T2 done"
refuses "defer a task that is already done" "$LEO" defer T2 "why"

printf '\nleo defer — a deferred task must be genuinely out of the way\n'

# The whole point: the loop steps over it. If `task_current` still returned a
# deferred task, `leo check` would go on demanding a grill for work nobody
# intends to do, and the deferral would be a label rather than a state.
set_status .leo/plans/P1/plan.md T2 pending
out=$("$LEO" session --report 2>&1)
says "$out" "T2" "the reminder moved on to the next task"
printf '%s' "$out" | grep -q 'Next.*T1' \
  && bad "the reminder still points at the deferred T1" \
  || ok "the reminder does not point at the deferred task"

# And a deferred task must not be buildable without resuming it: a task file
# is the thing that turns a plan row into work.
refuses "leo task on a deferred task" "$LEO" task T1

printf '\nleo resume — refusing what is not deferred\n'

refuses "resume a task that was never deferred" "$LEO" resume T2
refuses "resume an id the plan does not have" "$LEO" resume T99
refuses "resume with no argument" "$LEO" resume
accepts "resume a genuinely deferred task" "$LEO" resume T1
refuses "resume the same task twice" "$LEO" resume T1
n=$(grep -c '^- T1 ' .leo/plans/P1/plan.md || true)
[ "${n:-0}" -eq 0 ] && ok "resuming took the Later line back out" \
                    || bad "the Later line survived the resume"

printf '\nsubtask deferral — the grill gate must not punish parked work\n'

"$LEO" task T1 >/dev/null 2>&1
"$LEO" task T1 --sub "one" >/dev/null 2>&1
"$LEO" task T1 --sub "two" >/dev/null 2>&1

refuses "defer a subtask that does not exist" "$LEO" defer T1.9 "why"
refuses "defer a subtask of a task with no file" "$LEO" defer T2.1 "why"
accepts "defer a real subtask" "$LEO" defer T1.2 "needs its own grill"
refuses "defer the same subtask twice" "$LEO" defer T1.2 "again"
n=$(grep -c '^Status: later' .leo/plans/P1/tasks/T1.md || true)
[ "${n:-0}" -eq 1 ] && ok "the refused second subtask deferral wrote nothing" \
                    || bad "T1.md has $n Status lines, expected 1"

# The gate itself. Three ungrilled markers exist -- the task's own, T1.1's and
# T1.2's -- and the deferred one must not count. Grilling work that is
# explicitly not happening means answering questions about code nobody will
# write, which is the failure the grill exists to prevent, arriving through
# the gate that enforces it.
before=$("$LEO" check 2>&1 | grep -o 'ungrilled ([0-9]* section' | grep -o '[0-9]*' || true)
[ "${before:-0}" -eq 2 ] \
  && ok "the deferred subtask is excluded from the grill count (2, not 3)" \
  || bad "the grill counted ${before:-?} sections, expected 2"

accepts "resume the subtask" "$LEO" resume T1.2
after=$("$LEO" check 2>&1 | grep -o 'ungrilled ([0-9]* section' | grep -o '[0-9]*' || true)
[ "${after:-0}" -eq 3 ] \
  && ok "resuming puts the subtask back under the gate (3)" \
  || bad "the grill counted ${after:-?} sections after resume, expected 3"

printf '\nnumbered plans — ids must never collide or restart\n'

"$LEO" plan "second change" >/dev/null 2>&1
[ -f .leo/plans/P2/plan.md ] && ok "a new goal opened P2" || bad "P2 was not created"

first=$(grep -o '^| T[0-9]*' .leo/plans/P2/plan.md | head -1 | tr -d '| ')
[ "$first" = "T3" ] \
  && ok "P2's tasks continue the numbering (T3), they do not restart" \
  || bad "P2 starts at $first — ids restarted, and T1 now means two things"

refuses "switch to a plan that does not exist" "$LEO" plan --switch P99
refuses "switch with no id" "$LEO" plan --switch
refuses "an unknown plan flag" "$LEO" plan --nonsense

# A task belonging to another plan. The naive failure is "T1 is not in the
# plan", which is true and sends somebody editing P2's table to add a row that
# already exists one directory over.
out=$("$LEO" task T1 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a task from another plan is refused" \
                || bad "P1's T1 was accepted while P2 is in flight"
says "$out" "P1" "the refusal names the plan that owns it"

accepts "switching back to P1" "$LEO" plan --switch P1

printf '\nthe plan is not part of the change it describes\n'

# .leo/plans/ is tracked, unlike everything else leo writes, so the plan and
# its task files arrive in git diff like any other file. Before this was
# handled, `leo scan` opened every cycle with two rows asking "why does this
# hunk exist" about the document that answers that question for every other
# row, and the budget measured the change against an estimate its own prose
# was inflating.
accepts "back to P1 for the scan" "$LEO" plan --switch P1
rm -f .leo/manifest.md
printf 'real = 1\n' > real.py
"$LEO" scan >/dev/null 2>&1
grep -q 'real.py' .leo/manifest.md \
  && ok "the scan lists the file that actually changed" \
  || bad "the scan missed real.py"
grep -q '\.leo/plans/' .leo/manifest.md \
  && bad "the scan enumerated the plan as a hunk of its own change" \
  || ok "the scan does not enumerate the plan as a hunk"

# ...but everything else under .leo/ is repository code somebody wrote on
# purpose, and a blanket filter would quietly stop reviewing it.
printf 'x\n' > .leo/rules/NEG-VISIBLE.md
rm -f .leo/manifest.md
"$LEO" scan >/dev/null 2>&1
grep -q 'NEG-VISIBLE' .leo/manifest.md \
  && ok ".leo/rules/ is still reviewed — the exclusion is plans/, not .leo/" \
  || bad ".leo/rules/ dropped out of the manifest with the plans"
rm -f .leo/rules/NEG-VISIBLE.md real.py .leo/manifest.md

printf '\nleo agents — a stale block must not be believed\n'

refuses "an unknown agents flag" "$LEO" agents --nonsense
refuses "a positional argument agents does not take" "$LEO" agents foo

accepts "writing the block" "$LEO" agents --auto
accepts "the block is current straight afterwards" "$LEO" agents --check

# The whole reason the fingerprint exists. The developer changes the session;
# AGENTS.md now describes a session nobody is in, and an agent reading it will
# use a tool that was switched off.
"$LEO" session --mode debugging >/dev/null 2>&1
refuses "the block is stale after the mode changes" "$LEO" agents --check
out=$("$LEO" check 2>&1 || true)
says "$out" "stale instructions" "leo check fails on a stale tools block"

accepts "refreshing settles it" "$LEO" agents --auto
accepts "and check agrees again" "$LEO" agents --check

# Writing the block must not change what leo detects. ponytail_present greps
# AGENTS.md, and `leo agents` writes the word "ponytail" into AGENTS.md: the
# tool detected itself the moment leo described it, and the fingerprint moved
# between being computed and being written.
fp1=$(sed -n 's/.*fingerprint=\([a-z0-9]*\).*/\1/p' AGENTS.md | head -1)
"$LEO" agents --auto >/dev/null 2>&1
fp2=$(sed -n 's/.*fingerprint=\([a-z0-9]*\).*/\1/p' AGENTS.md | head -1)
[ "$fp1" = "$fp2" ] \
  && ok "writing the block does not change what leo detects" \
  || bad "the fingerprint moved just by writing it: $fp1 -> $fp2"

# A block the developer hand-edited is still theirs outside the markers.
printf '\nDEVELOPER-WROTE-THIS\n' >> AGENTS.md
"$LEO" agents --auto >/dev/null 2>&1
grep -q 'DEVELOPER-WROTE-THIS' AGENTS.md \
  && ok "regenerating the block leaves the rest of AGENTS.md alone" \
  || bad "leo agents ate something the developer wrote"

printf '\nleo docs — a missing companion document must be visible\n'

refuses "an unknown docs flag" "$LEO" docs --nonsense
accepts "docs --check passes on a complete repository" "$LEO" docs --check

mv ARCHITECTURE.md "$TMP/arch-hidden"
refuses "docs --check fails when a document is deleted" "$LEO" docs --check
out=$("$LEO" check 2>&1 || true)
says "$out" "ARCHITECTURE" "leo check names the missing document"
accepts "docs --write puts it back" "$LEO" docs --write
[ -f ARCHITECTURE.md ] && ok "ARCHITECTURE.md exists again" \
                       || bad "docs --write did not restore it"

# The rule index is generated. A hand-kept copy beside .leo/rules/ drifts the
# first time somebody adds a rule in a hurry, which is when rules get added.
cat > .leo/rules/NEG-EXAMPLE.md <<'RULE'
# MUST NOT ship a rule nobody indexed

Learned from: this test.

## Verify

```sh
true
```
RULE
"$LEO" docs --write >/dev/null 2>&1
grep -q 'NEG-EXAMPLE' RULES.md \
  && ok "a new rule appears in the generated index" \
  || bad "RULES.md does not list the rule that was just added"
rm -f .leo/rules/NEG-EXAMPLE.md
"$LEO" docs --write >/dev/null 2>&1
grep -q 'NEG-EXAMPLE' RULES.md \
  && bad "RULES.md still lists a rule that was deleted" \
  || ok "a deleted rule leaves the generated index"

printf '\nSESSION.md — written at all costs, especially on failure\n'

# This is the one the feature was asked for. The moment SESSION.md is worth
# anything is the moment after something went wrong, and that is exactly the
# moment a command exits early. Every one of these must still leave the file
# behind.
for probe in \
  "check" \
  "defer T99 nope" \
  "resume T99" \
  "plan --switch P99" \
  "agents --nonsense" \
  "task banana" \
  "use no-such-tool" \
  "scan not-a-revision" \
  ; do
  rm -f SESSION.md
  # shellcheck disable=SC2086
  "$LEO" $probe >/dev/null 2>&1 || true
  if [ -f SESSION.md ]; then
    ok "SESSION.md survives a failing: leo $probe"
  else
    bad "SESSION.md missing after a failing: leo $probe"
  fi
done

# ...and on a command that succeeds, and on one that does nothing at all.
for probe in "help" "plan --list" "session --report" "task" "defer --list"; do
  rm -f SESSION.md
  # shellcheck disable=SC2086
  "$LEO" $probe >/dev/null 2>&1 || true
  [ -f SESSION.md ] && ok "SESSION.md written by: leo $probe" \
                    || bad "SESSION.md missing after: leo $probe"
done

# A truncated status file is worse than a stale one, because it looks current.
# The write goes to a temp file and is moved into place for exactly this.
rm -f SESSION.md
"$LEO" session --report >/dev/null 2>&1
tail -1 SESSION.md | grep -q '.' \
  && ok "SESSION.md is written whole, not truncated" \
  || bad "SESSION.md ends in nothing — the write was not atomic"

# It must describe THIS session, not a remembered one. Content AND mtime: an
# unchanged file is the symptom of the bug this caught, where session_doc's
# loop variable overwrote the path session_doc_write was about to move the
# document to, so the write went somewhere else and the stale file stayed put
# looking perfectly plausible.
"$LEO" defer T2 "parked for the test" >/dev/null 2>&1
grep -q 'T2' SESSION.md \
  && ok "SESSION.md carries the deferral that just happened" \
  || bad "SESSION.md does not mention a deferral made one command ago"

# Inode, not mtime. `ls -l` prints minutes, and two writes a second apart look
# identical to it -- the check would pass on a file that was never touched.
# Every write here ends in `mv`, so a rewrite is always a new inode.
before=$(ls -i SESSION.md 2>/dev/null | awk '{print $1}')
"$LEO" plan --list >/dev/null 2>&1
after=$(ls -i SESSION.md 2>/dev/null | awk '{print $1}')
[ -n "$before" ] && [ "$before" != "$after" ] \
  && ok "SESSION.md is rewritten while later work exists, not left stale" \
  || bad "SESSION.md was not rewritten (inode $before -> $after)"

# And nothing stray was created where the document should have gone.
[ -e T2 ] && bad "a file called T2 appeared — the move target was clobbered" \
          || ok "no stray file from a clobbered move target"

# Readable by whoever else works in this checkout. mktemp makes 0600 and mv
# carries the mode across, so this needs saying out loud.
perm=$(ls -l SESSION.md | cut -c1-10)
case "$perm" in
  -rw-r--r--) ok "SESSION.md is readable by others ($perm)" ;;
  *)          bad "SESSION.md is $perm — mktemp's 0600 came along for the ride" ;;
esac

"$LEO" resume T2 >/dev/null 2>&1

# The exit hook must not swallow the exit code it was called with. A check
# that fails and reports success is the worst possible outcome of a feature
# whose entire job is to run on the way out of a failure.
printf 'unreviewed\n' > unreviewed.txt
rm -f .leo/manifest.md
"$LEO" scan >/dev/null 2>&1
"$LEO" check >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "the exit hook preserves a failing exit code" \
                || bad "leo check reported success on an unreviewed manifest"
rm -f unreviewed.txt .leo/manifest.md

printf '\none EXIT trap, or SESSION.md stops being written\n'

# `trap ... EXIT` does not stack: the last one installed silently replaces
# every earlier one. A command that installs its own would take the session
# document with it, and the failure would be invisible -- the command still
# works, the file just quietly stops being current.
# Comments may discuss the pattern; this is about code that runs it. Same
# exclusion as .leo/rules/ONE-EXIT-TRAP.md, which is the durable copy -- this
# is here so the suite catches it without a leo repository to run rules in.
# The same rule, against the mechanism that replaced the shell trap: Node's
# process.on('exit') does stack rather than silently replacing, so the failure
# is no longer "the last one wins" -- it is a second handler running after the
# session document is written, in a handler that cannot await anything. One
# place registers it, and src/lib/exit.js is that place.
hits=$(grep -rn "process\.on( *['\"]exit" "$LEOHOME/src/" 2>/dev/null \
       | grep -v '^[^:]*src/lib/exit\.js:' \
       | grep -v '^[^:]*:[0-9]*: *//' || true)
[ -z "$hits" ] && ok "no command installs an exit handler of its own" \
               || bad "exit handler outside src/lib/exit.js: $hits"

printf '\npackaging\n'
if bash "$LEOHOME/t/package.sh" >"$TMP/pkg.out" 2>&1; then
  ok "the npm package would ship a leo that runs"
else
  bad "packaging test failed:"
  sed 's/^/        /' "$TMP/pkg.out"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
