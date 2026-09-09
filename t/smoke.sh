#!/usr/bin/env bash
# Smoke test: drive the real CLI through a real repository.
#
# Its main job is the boring one -- proving that `leo check` still SAYS
# something in every combination of missing plan and missing manifest. Under
# `set -e` with `pipefail`, one grep that legitimately matches nothing is enough
# to kill the command mid-run and print nothing at all, which looks exactly like
# success to a script and exactly like a hang to a person.

set -u
LEOHOME=$(cd -P "$(dirname "$0")/.." && pwd)
LEO="$LEOHOME/leo"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/leo-smoke.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

ok()   { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

# check <label> <expected-rc> -- run `leo check`, require it to speak.
check() {
  _out=$(cd "$TMP/repo" && NO_COLOR=1 "$LEO" check 2>&1); _rc=$?
  _lines=$(printf '%s' "$_out" | grep -c .)
  if [ "$_lines" -lt 4 ]; then
    bad "$1: check died silently (rc=$_rc, $_lines lines)"
  elif [ "$_rc" != "$2" ]; then
    bad "$1: expected rc=$2, got rc=$_rc"
  else
    ok "$1"
  fi
}

has() { printf '%s' "$1" | grep -q "$2" && ok "$3" || bad "$3"; }

mkdir -p "$TMP/repo" && cd "$TMP/repo"
git init -q . && git config user.email t@t && git config user.name t
echo one > f.txt && git add -A && git commit -qm init

printf 'setup\n'
out=$(NO_COLOR=1 "$LEO" init 2>&1)
has "$out" "ready" "init scaffolds a repo"
printf 'TEST_CMD="true"\n' >> .leo/config
git add -A && git commit -qm adopt
echo two >> f.txt

printf 'check survives every missing-file combination\n'
rm -f .leo/plan.md .leo/manifest.md
check "no plan, no manifest" 0

printf '# Plan\n\n| T1 | a | b | 5 | pending |\n\nest: 20 LOC\n' > .leo/plan.md
check "plan, no manifest" 0

NO_COLOR=1 "$LEO" scan >/dev/null 2>&1
check "plan + unreviewed manifest" 1

sed 's/|  |  |  |/| T1 | because | it breaks |/' .leo/manifest.md > "$TMP/m" && mv "$TMP/m" .leo/manifest.md
check "plan + reviewed manifest" 0

rm -f .leo/plan.md
check "manifest, no plan" 0

printf '# Plan\n\n| T1 | a | b | 5 | pending |\n' > .leo/plan.md
check "plan with no estimate" 0

printf '# Plan\n\nest: 20 LOC\n' > .leo/plan.md
check "plan with no task rows" 0

# An untracked binary or empty file used to kill check on the budget line:
# is_text fails, the while loop in lines_changed returns 1, pipefail fails the
# substitution and `set -e` takes the whole command down after the number was
# already computed. A .pyc or a .DS_Store was enough.
printf '\000\001\002' > blob.bin
: > empty.txt
check "untracked binary and empty file" 0
has "$(NO_COLOR=1 "$LEO" check 2>&1)" "est .* actual" "the budget line survives an untracked binary"
rm -f blob.bin empty.txt

printf 'check catches what it is for\n'
printf '# Plan\n\n| T1 | a | b | 5 | pending |\n\nest: 20 LOC\n' > .leo/plan.md
sed 's/| T1 |/| T9 |/' .leo/manifest.md > "$TMP/m" && mv "$TMP/m" .leo/manifest.md
out=$(NO_COLOR=1 "$LEO" check 2>&1)
has "$out" "T9 is not a task in the plan" "rejects an invented task ID"

sed 's/| T9 |/| - |/' .leo/manifest.md > "$TMP/m" && mv "$TMP/m" .leo/manifest.md
out=$(NO_COLOR=1 "$LEO" check 2>&1)
has "$out" "serve no task" "reports unmapped hunks in lines"

for i in 1 2 3 4 5 6 7 8 9 10; do echo "line $i" >> f.txt; done
printf '# Plan\n\n| T1 | a | b | 1 | pending |\n\nest: 1 LOC\n' > .leo/plan.md
out=$(NO_COLOR=1 "$LEO" check 2>&1)
has "$out" "over 2x" "fails a budget overshoot"

printf 'the session declares, and changes nothing else\n'
out=$(NO_COLOR=1 "$LEO" session 2>&1)
has "$out" "no session" "session says so when there is none"

NO_COLOR=1 "$LEO" session --mode debugging >/dev/null 2>&1
has "$(cat .leo/session)" "MODE=debugging" "--mode writes the session"
out=$(NO_COLOR=1 "$LEO" session 2>&1)
has "$out" "Headroom  *OFF" "debugging leaves the semantic reducers off"
has "$out" "Human commit  *ON" "the controls show as always on"

NO_COLOR=1 "$LEO" session --caveman on >/dev/null 2>&1
has "$(cat .leo/session)" "CAVEMAN=on" "an override is recorded"
NO_COLOR=1 "$LEO" session --mode review >/dev/null 2>&1
grep -q CAVEMAN .leo/session \
  && bad "a new mode resets the overrides" || ok "a new mode resets the overrides"

NO_COLOR=1 "$LEO" session --mode nope >/dev/null 2>&1 \
  && bad "rejects an unknown mode" || ok "rejects an unknown mode"
NO_COLOR=1 "$LEO" session --clear >/dev/null 2>&1
[ -f .leo/session ] && bad "--clear ends the session" || ok "--clear ends the session"

# The plan's wrong-change signal: the session is provenance, not a gate. If
# `leo check` ever reads it for anything but the one line it prints on failure,
# this is the test that says so.
a=$(NO_COLOR=1 "$LEO" check 2>&1); arc=$?
NO_COLOR=1 "$LEO" session --mode coding >/dev/null 2>&1
b=$(NO_COLOR=1 "$LEO" check 2>&1); brc=$?
b=$(printf '%s\n' "$b" | grep -v 'session mode:')
if [ "$arc" = "$brc" ] && [ "$a" = "$b" ]; then
  ok "check behaves identically with and without a session"
else
  bad "check behaves identically with and without a session (rc $arc vs $brc)"
fi
NO_COLOR=1 "$LEO" session --clear >/dev/null 2>&1

printf 'adapters detect, and never gate\n'
out=$(NO_COLOR=1 "$LEO" session --mode debugging 2>&1)
has "$out" "Serena  *MISSING" "an enabled tool that is absent reads as MISSING"
has "$out" "uv tool install" "a missing tool comes with the install line"
has "$out" "Code graph  *MISSING" "the code graph reads as installable, not unsupported"

# Bug that shipped once: cap_present returning non-zero in statement position
# killed the whole block under `set -e`, so dependencies printed a header and
# nothing else on every machine where a tool was missing -- the common case.
n=$(printf '%s\n' "$out" | sed -n '/dependencies/,$p' | grep -c .)
[ "$n" -gt 4 ] && ok "the dependencies block survives a missing tool" \
                || bad "the dependencies block survives a missing tool ($n lines)"

# And the other half of it: grep returns 2 for a missing file, which is leo's
# own code for "no adapter". An adapter must not be able to claim that.
mkdir -p "$TMP/bin" && printf '#!/bin/sh\n' > "$TMP/bin/serena" && chmod +x "$TMP/bin/serena"
out=$(PATH="$TMP/bin:$PATH" NO_COLOR=1 "$LEO" session 2>&1)
has "$out" "Serena  *installed" "an installed tool is detected"
has "$out" "serena --mode" "an installed tool comes with advice, not an install line"
out=$(NO_COLOR=1 "$LEO" session --mode coding 2>&1)
has "$out" "Ponytail  *MISSING" "an adapter that greps a missing file reads as MISSING"

printf 'the report reads state, it does not invent it\n'
out=$(NO_COLOR=1 "$LEO" session --report 2>&1)
has "$out" "Mode  *coding" "report names the mode"
has "$out" "Approval" "report names who approves"
# Deliberately narrow: the report is allowed to say the word "token" while
# explaining why it prints no number. What it must never contain is a figure.
printf '%s' "$out" | grep -Eqi '[0-9]+ *%|tokens? saved|savings|reduction' \
  && bad "report states no savings figure" || ok "report states no savings figure"

# leo has to work with none of these installed. That is the whole dependency
# philosophy, and it is one assertion.
out=$(PATH="/usr/bin:/bin" NO_COLOR=1 "$LEO" check 2>&1); rc=$?
[ "$rc" = 0 ] || [ "$rc" = 1 ] && ok "check runs with no integration on PATH" \
                              || bad "check runs with no integration on PATH (rc=$rc)"
NO_COLOR=1 "$LEO" session --clear >/dev/null 2>&1

printf 'install is a command, never a side effect\n'
out=$(NO_COLOR=1 "$LEO" install 2>&1)
has "$out" "serena  *missing" "install lists a tool it knows how to install"
has "$out" "graph  *missing" "the code graph has an adapter now"

out=$(unset LEO_YES; NO_COLOR=1 "$LEO" install serena </dev/null 2>&1); rc=$?
has "$out" "needs a human at a terminal" "install refuses without a tty"
[ "$rc" = 2 ] && ok "install exits 2 when refused" || bad "install exit was $rc, wanted 2"

# The property the whole design rests on: nothing except `leo install` may
# touch the machine, and it cannot run unattended.
for c in session scan check; do
  out=$(unset LEO_YES; NO_COLOR=1 "$LEO" $c </dev/null 2>&1 || true)
  printf '%s' "$out" | grep -qiE 'installing|brew install|uv tool install|curl -fsSL.*\| *(sh|bash)$' \
    && bad "leo $c never installs anything" || ok "leo $c never installs anything"
done

printf 'a repository can add a tool leo has never heard of\n'
mkdir -p .leo/integrations
cat > .leo/integrations/zzdemo.sh <<'ADAPTER'
zzdemo_present() { command -v zzdemo-not-real >/dev/null 2>&1; }
zzdemo_label()   { printf 'ZZ Demo'; }
zzdemo_hint()    { say "not a real tool"; }
zzdemo_default() { case "$1" in review) printf 'on' ;; *) printf 'off' ;; esac; }
ADAPTER
out=$(NO_COLOR=1 "$LEO" session --mode review 2>&1)
has "$out" "extensions" "an extension gets its own heading"
has "$out" "ZZ Demo  *ON" "the adapter's own label and per-mode default are used"
out=$(NO_COLOR=1 "$LEO" session --mode coding 2>&1)
has "$out" "ZZ Demo  *OFF" "a mode the adapter does not name defaults it off"
out=$(NO_COLOR=1 "$LEO" session --zzdemo on 2>&1)
has "$out" "ZZ Demo  *ON  *(you)" "an extension can be overridden like a built-in"

# The wrong-change signal from the plan, stated as a test: a broken adapter in
# a repository must not be able to break leo. If this ever fails, extensions
# have become a plugin framework and should be taken back out.
a=$(NO_COLOR=1 "$LEO" check 2>&1); arc=$?
printf 'zzbroken_present() { unbalanced "\n' > .leo/integrations/zzbroken.sh
out=$(NO_COLOR=1 "$LEO" session 2>&1)
has "$out" "does not parse" "a broken adapter is reported"
printf '%s' "$out" | grep -q 'zzbroken' && ok "a broken adapter is named" || bad "a broken adapter is named"

# Not "check still exits 0" -- "check does exactly what it did before". The
# adapter is a repository file leo sources on every command, so the property
# worth asserting is that it changes nothing at all.
b=$(NO_COLOR=1 "$LEO" check 2>&1); brc=$?
# Drop the adapter warning and the budget line: the adapter file is a real new
# file in the repository, so it legitimately moves the line count. Everything
# else -- rules, manifest, tests, verdict -- must be identical.
a=$(printf '%s\n' "$a" | grep -v 'actual')
b=$(printf '%s\n' "$b" | grep -v 'does not parse' | grep -v 'actual')
if [ "$arc" = "$brc" ] && [ "$a" = "$b" ]; then
  ok "a broken adapter changes nothing about check"
else
  bad "a broken adapter changes nothing about check (rc $arc vs $brc)"
fi
rm -rf .leo/integrations
NO_COLOR=1 "$LEO" session --clear >/dev/null 2>&1

printf 'TDD is a capability, not a rule\n'
# It is available when the repository can actually run its tests. A repo with
# no TEST_CMD cannot do test-first, and a green light there would be a lie.
printf 'TEST_CMD="true"\n' > .leo/config
out=$(NO_COLOR=1 "$LEO" session --mode coding 2>&1)
has "$out" "TDD  *ON" "TDD is on in coding"
has "$out" "TDD  *installed" "TEST_CMD is what installed means for TDD"
has "$out" "practice" "TDD gets its own group, not filed under efficiency"
out=$(NO_COLOR=1 "$LEO" session --mode review 2>&1)
has "$out" "TDD  *OFF" "TDD is off in a mode that writes no code"
# The ponytail bug, again: a _present that ends in a bare test against a
# missing thing exits 2, which is leo's code for "no adapter".
printf 'TEST_CMD=""\n' > .leo/config
out=$(NO_COLOR=1 "$LEO" session --mode coding 2>&1)
has "$out" "TDD  *MISSING" "no TEST_CMD reads as MISSING, never as no-adapter"
printf 'TEST_CMD="true"\n' > .leo/config

printf 'a task has its own file and its own to-do\n'
printf '# Plan: x\n\n| T1 | first | f.txt | 5 | pending |\n| T2 | second | f.txt | 5 | pending |\n\nest: 20 LOC\n' > .leo/plan.md
NO_COLOR=1 "$LEO" session --mode coding --tdd off >/dev/null 2>&1
out=$(NO_COLOR=1 "$LEO" task T1 2>&1)
[ -f .leo/tasks/T1.md ] && ok "leo task creates the task file" || bad "leo task creates the task file"
out=$(cat .leo/tasks/T1.md 2>/dev/null)
has "$out" "Done when" "the task file is a template the agent fills"
has "$out" "To-do" "the task file carries its own to-do"
# The duplication guard, and the one this change is most likely to violate:
# the plan's Status column is the authority, so a task file must not have one.
printf '%s' "$out" | grep -q '^Status' \
  && bad "the task file does not restate Status" \
  || ok "the task file does not restate Status"
out=$(NO_COLOR=1 "$LEO" task 2>&1)
has "$out" "T1" "leo task lists the tasks"
has "$out" "0/" "leo task tracks to-do progress"

printf 'the TDD capability seeds the to-do\n'
NO_COLOR=1 "$LEO" session --mode coding --tdd on >/dev/null 2>&1
NO_COLOR=1 "$LEO" task T2 >/dev/null 2>&1
out=$(cat .leo/tasks/T2.md 2>/dev/null)
has "$out" "FAIL" "with TDD on, the to-do starts with a failing test"
NO_COLOR=1 "$LEO" session --tdd off >/dev/null 2>&1
NO_COLOR=1 "$LEO" task T2 --force >/dev/null 2>&1
out=$(cat .leo/tasks/T2.md 2>/dev/null)
printf '%s' "$out" | grep -q 'watch it FAIL' \
  && bad "with TDD off the to-do is not seeded" \
  || ok "with TDD off the to-do is not seeded"
# Never clobber work: the same rule leo plan already follows.
NO_COLOR=1 "$LEO" task T1 >/dev/null 2>&1
out=$(NO_COLOR=1 "$LEO" task T1 2>&1)
has "$out" "Done when" "a second leo task shows the file instead of replacing it"

printf 'cycle two: a review of a commit that has landed\n'
# The whole cycle, end to end, against a real commit -- opening the review,
# every way --close refuses, and the close itself.
cd "$TMP/repo"
# Start from a clean tree. Everything above left uncommitted work behind, and
# `leo commit` runs `leo check` -- an inherited budget overshoot would fail the
# commit and every assertion below it would then be testing the wrong commit.
rm -f .leo/plan.md .leo/manifest.md
printf 'TEST_CMD="true"\n' > .leo/config
git add -A >/dev/null 2>&1 && git commit -qm "clean slate for cycle two" >/dev/null 2>&1
cat > risky.py <<'RISKY'
SECRET_KEY = "sk-live-000111222333"
def run(name):
    import subprocess
    subprocess.run("id " + name, shell=True)
RISKY
printf '# Plan: risky\n\n## Goal\n\nAdd a runner.\n\n## Non-goals\n\nAuthentication.\n\n| T1 | runner | risky.py | 5 | done |\n\nest: 20 LOC\n' > .leo/plan.md
mkdir -p .leo/tasks
printf '# T1: runner\n\n## Grill\n\nShell out because the API has no binding.\n\n## To-do\n\n- [x] done\n' > .leo/tasks/T1.md
NO_COLOR=1 "$LEO" scan >/dev/null 2>&1
sed 's/|  |  |  |/| T1 | asked for | it breaks |/' .leo/manifest.md > "$TMP/m" && mv "$TMP/m" .leo/manifest.md
LEO_YES=1 NO_COLOR=1 "$LEO" commit "feat: runner" >/dev/null 2>&1
sha=$(git rev-parse --short HEAD)

out=$(NO_COLOR=1 "$LEO" review "$sha" 2>&1)
has "$out" "opened .leo/reviews/$sha.md" "leo review opens a review of a commit"
[ -f ".leo/reviews/$sha.md" ] && ok "the review is a file" || bad "the review is a file"
r=$(cat ".leo/reviews/$sha.md")

# Briefed, not blank. Each of these comes from a different place in cycle one,
# and any one of them going missing is silent.
has "$r" "feat: runner"        "the review names the commit it reviews"
has "$r" "Add a runner"        "the goal comes across from the commit message"
has "$r" "asked for"           "the manifest comes across from the commit message"
has "$r" "Authentication"      "the non-goals come across from the plan"
has "$r" "no binding"          "what the grill settled comes across from the task file"

# Signals. These are greps, and a grep that silently stops matching is the
# failure nobody notices -- so one of them is asserted by line number.
has "$r" "risky.py:1"          "a secret-shaped literal is flagged, with its line"
has "$r" "shell=True"          "an interpreter call is flagged"
has "$r" "0 test file"         "a change with no test file changed says so"

# `leo review` must never be able to touch the code it reviews.
git diff --quiet HEAD && ok "leo review changes nothing in the worktree" \
                       || bad "leo review changes nothing in the worktree"

# Opening it twice shows it rather than replacing what was written.
printf 'MARKER-NOT-CLOBBERED\n' >> ".leo/reviews/$sha.md"
NO_COLOR=1 "$LEO" review "$sha" >/dev/null 2>&1
has "$(cat ".leo/reviews/$sha.md")" "MARKER-NOT-CLOBBERED" \
  "a second leo review shows the file instead of replacing it"

printf 'cycle two refuses in exactly three ways\n'
f=".leo/reviews/$sha.md"
close() { NO_COLOR=1 "$LEO" review --close 2>&1; }

# 1. the verdict is still the template's placeholder
out=$(close || true)
has "$out" "states no verdict" "refuses while the verdict is the placeholder"

# 2. a severity or status outside the vocabulary. The gate reads two columns of
# a markdown table, and a word it cannot parse must fail loudly, not silently.
awk '/^\|---\|/{print; print "| 1 | critical | `risky.py:1` | key | it is live | nope |"; next}1' "$f" > "$TMP/f" && mv "$TMP/f" "$f"
out=$(close || true)
has "$out" "is not blocker/improvement/nit" "refuses a severity it cannot parse"
awk '/^\| 1 \|/{print "| 1 | blocker | `risky.py:1` | live key committed | it must be rotated, not deleted | nope |"; next}1' "$f" > "$TMP/f" && mv "$TMP/f" "$f"
out=$(close || true)
has "$out" "is not open/fixed/waived" "refuses a status it cannot parse"

# 3. a blocker nobody dispositioned
awk '/^\| 1 \|/{sub(/\| nope \|$/, "| open |")}1' "$f" > "$TMP/f" && mv "$TMP/f" "$f"
sed 's/^Verdict: <.*/Verdict: fix-first -- read risky.py against the standards./' "$f" > "$TMP/f" && mv "$TMP/f" "$f"
out=$(close || true)
has "$out" "blocker(s) still open" "refuses while a blocker is open"
has "$out" "a fix is a dev cycle" "names the hand-off back to cycle one"
rc=0; NO_COLOR=1 "$LEO" review --close >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] && ok "an open review exits 1" || bad "an open review exited $rc, wanted 1"

printf 'cycle two closes, and stays closed\n'
awk '/^\| 1 \|/{sub(/\| open \|$/, "| waived |")}1' "$f" > "$TMP/f" && mv "$TMP/f" "$f"
out=$(close)
has "$out" "closes" "closes once every finding is dispositioned"
has "$out" "waived" "a waived blocker is reported, not hidden"
has "$(cat "$f")" "^Closed: 2" "closing stamps the file"
# The bug this pair exists for: state and target were once the same predicate,
# so a review that met every closing condition became invisible to --close and
# could never be closed at all.
has "$(NO_COLOR=1 "$LEO" review --list 2>&1)" "closed" "a closed review lists as closed"
out=$(close || true)
has "$out" "no open review" "a closed review is not offered again"

printf 'the awkward inputs\n'
# awk runs END on `exit`, so a rule that prints and exits mid-file prints a
# SECOND time from END. task_current did exactly that: a pending task before an
# in-progress one returned both ids, and the reminder then named a task file
# whose path had a newline in it.
printf '# Plan: x\n\n| T1 | first | f.txt | 5 | pending |\n| T2 | second | f.txt | 5 | in-progress |\n\nest: 20 LOC\n' > .leo/plan.md
rm -f .leo/tasks/*.md
out=$(NO_COLOR=1 "$LEO" session --report 2>&1)
# The stray id lands on its own line, so counting "leo task" would miss it.
printf '%s' "$out" | grep -qx '[ \t]*T[0-9]*' \
  && bad "the current task is one task, not two" \
  || ok "the current task is one task, not two"
has "$out" "leo task T2" "the current task is the in-progress one"

# gsub's replacement treats & as the matched text. A task named "a & b" came
# out as "a <NAME> b" -- the same class of bug the code comments claim awk
# avoids, which is why it is asserted rather than trusted.
printf '# Plan: x\n\n| T1 | rate limit & retry | a/b.go | 5 | pending |\n\nest: 20 LOC\n' > .leo/plan.md
rm -f .leo/tasks/T1.md
NO_COLOR=1 "$LEO" task T1 >/dev/null 2>&1
out=$(cat .leo/tasks/T1.md 2>/dev/null)
has "$out" "rate limit & retry" "an ampersand in a task name survives the template"
# The other metacharacter that bites here: a backslash in a file list.
printf '# Plan: x\n\n| T2 | second | a\\b.go | 5 | pending |\n\nest: 20 LOC\n' > .leo/plan.md
rm -f .leo/tasks/T2.md
NO_COLOR=1 "$LEO" task T2 >/dev/null 2>&1
has "$(cat .leo/tasks/T2.md 2>/dev/null)" 'a.b.go' "a backslash in a file list does not eat a character"

# A task the plan does not list is created with a warning, never refused:
# the moment leo can refuse here, the to-do is paperwork.
rm -f .leo/tasks/T9.md
out=$(NO_COLOR=1 "$LEO" task T9 2>&1)
has "$out" "not in the plan" "an unplanned task warns"
[ -f .leo/tasks/T9.md ] && ok "an unplanned task is still created" \
                        || bad "an unplanned task is still created"
out=$(NO_COLOR=1 "$LEO" task nonsense 2>&1) && rc=0 || rc=$?
has "$out" "task ids are" "a malformed task id is rejected"
[ "$rc" = 1 ] && ok "a malformed task id exits 1" || bad "a malformed id exit was $rc"

# No session at all: leo task must still work, ungated, with no TDD seeding.
NO_COLOR=1 "$LEO" session --clear >/dev/null 2>&1
rm -f .leo/tasks/T1.md
NO_COLOR=1 "$LEO" task T1 >/dev/null 2>&1
[ -f .leo/tasks/T1.md ] && ok "leo task works with no session" \
                        || bad "leo task works with no session"
rm -f .leo/tasks/T9.md .leo/tasks/T2.md

printf 'a finished to-do does not skip the rest of the plan\n'
# The gap this caught: T1's boxes all ticked but its Status still pending, and
# the reminder jumped straight to `leo scan` -- sending the change to the
# manifest with T2 never built at all.
printf '# Plan: x\n\n| T1 | first | f.txt | 5 | pending |\n| T2 | second | f.txt | 5 | pending |\n\nest: 20 LOC\n' > .leo/plan.md
rm -f .leo/tasks/*.md
NO_COLOR=1 "$LEO" session --mode coding >/dev/null 2>&1
NO_COLOR=1 "$LEO" task T1 >/dev/null 2>&1
sed 's/- \[ \]/- [x]/' .leo/tasks/T1.md > .leo/tasks/T1.tmp && mv .leo/tasks/T1.tmp .leo/tasks/T1.md
out=$(NO_COLOR=1 "$LEO" session --report 2>&1)
has "$out" "T1 to done" "a finished to-do asks for the plan status, not the manifest"
printf '%s' "$out" | grep -q 'Next.*leo scan' \
  && bad "a finished to-do does not jump to the manifest" \
  || ok "a finished to-do does not jump to the manifest"
# ...and once it is marked done, the next unbuilt task is what comes up.
sed 's/| T1 | first | f.txt | 5 | pending |/| T1 | first | f.txt | 5 | done |/' .leo/plan.md > .leo/p.tmp && mv .leo/p.tmp .leo/plan.md
out=$(NO_COLOR=1 "$LEO" session --report 2>&1)
has "$out" "leo task T2" "the next unbuilt task comes up once the previous is done"
rm -f .leo/tasks/*.md

printf 'the loop names the next stage\n'
rm -f .leo/plan.md .leo/manifest.md .leo/tasks/*.md
out=$(NO_COLOR=1 "$LEO" session --report 2>&1)
has "$out" "Next" "the report names the next stage"
has "$out" "leo plan" "with no plan, the next stage is the plan"
printf '# Plan: x\n\n| T1 | first | f.txt | 5 | pending |\n\nest: 20 LOC\n' > .leo/plan.md
out=$(NO_COLOR=1 "$LEO" session --report 2>&1)
has "$out" "leo task" "with a plan and no task file, the next stage is task creation"
NO_COLOR=1 "$LEO" task T1 >/dev/null 2>&1
out=$(NO_COLOR=1 "$LEO" session --report 2>&1)
has "$out" "To-do" "the report tracks the current task's to-do"
NO_COLOR=1 "$LEO" session --clear >/dev/null 2>&1

printf 'every capability ships one instruction file\n'
# The mechanism: init installs a doc per capability, and `leo session` points
# at it. The docs are where a tool's prerequisites and failure modes live --
# one home each, which is the property this whole change exists to protect.
_missing_doc=""
for c in serena graph rtk headroom ponytail caveman tdd; do
  [ -f ".leo/tools/$c.md" ] || _missing_doc="$_missing_doc $c"
done
[ -z "$_missing_doc" ] && ok "init installs a doc for every built-in capability" \
                       || bad "init installs a doc for every capability (missing:$_missing_doc)"
out=$(NO_COLOR=1 "$LEO" session --mode debugging 2>&1)
has "$out" "instructions: .leo/tools/serena.md" "an enabled MISSING tool points at its doc"
printf 'TEST_CMD="true"\n' > .leo/config
out=$(NO_COLOR=1 "$LEO" session --mode coding 2>&1)
has "$out" "instructions: .leo/tools/tdd.md" "an enabled installed tool points at its doc"
# An extension with no doc must print nothing, not a path to a missing file.
mkdir -p .leo/integrations
printf 'zzdemo_present() { return 1; }\nzzdemo_hint() { say "x"; }\nzzdemo_default() { printf on; }\n' > .leo/integrations/zzdemo.sh
out=$(NO_COLOR=1 "$LEO" session --mode coding 2>&1)
printf '%s' "$out" | grep -q 'tools/zzdemo.md' \
  && bad "a capability with no doc points at nothing" \
  || ok "a capability with no doc points at nothing"
rm -rf .leo/integrations

printf 'the workflow gates tool use on the session\n'
has "$(cat .leo/workflow.md)" "ON .*and installed" "the workflow says a tool must be ON and installed"
has "$(cat .leo/workflow.md)" ".leo/tools/" "the workflow sends the agent to the per-tool doc"

printf 'caveman is skill only\n'
# Verified by running the installer: npx skills add writes into the REPO at
# .agents/skills/caveman* with .claude/skills symlinks. `command -v caveman`
# could never have found it, which is why the capability read MISSING forever.
NO_COLOR=1 "$LEO" session --mode coding --caveman on >/dev/null 2>&1
out=$(NO_COLOR=1 "$LEO" session 2>&1)
has "$out" "Caveman  *MISSING" "with no skill installed, caveman is MISSING not no-adapter"
mkdir -p .agents/skills/caveman
out=$(NO_COLOR=1 "$LEO" session 2>&1)
has "$out" "Caveman  *installed" "the skill directory is what installed means for caveman"
rm -rf .agents
mkdir -p .claude/skills/caveman
out=$(NO_COLOR=1 "$LEO" session 2>&1)
has "$out" "Caveman  *installed" "the claude-scope symlink counts too"
rm -rf .claude
NO_COLOR=1 "$LEO" session --mode coding >/dev/null 2>&1

printf 'the code graph is called through its CLI\n'
printf '#!/bin/sh\n' > "$TMP/bin/codebase-memory-mcp" && chmod +x "$TMP/bin/codebase-memory-mcp"
out=$(PATH="$TMP/bin:$PATH" NO_COLOR=1 "$LEO" session --mode debugging 2>&1)
has "$out" "cli" "an installed code graph is told to use the CLI"
has "$out" "instructions: .leo/tools/graph.md" "and pointed at the standing order"

printf 'a prerequisite lives in exactly one place\n'
# The plan's wrong-change signal, as a test. Seven docs, seven adapters, a
# GUIDE and a README are four plausible homes for "rtk tree needs tree(1)",
# and leo has already been burned once by two documents written to overlap.
# The doc is the sole home; everything else points at it.
_dupes=""
for probe in "tree(1)" "gopls" "exclude_commands"; do
  n=$(grep -rl -- "$probe" "$LEOHOME/templates" "$LEOHOME/core" "$LEOHOME/GUIDE.md" "$LEOHOME/README.md" 2>/dev/null | grep -c .)
  [ "$n" -le 1 ] || _dupes="$_dupes $probe:$n"
done
[ -z "$_dupes" ] && ok "each prerequisite is stated in exactly one file" \
                 || bad "each prerequisite is stated in one file (dupes:$_dupes)"
# The gateway leo decided against must not appear in anything leo RUNS or
# tells the agent to do. templates/tools/caveman.md names it on purpose --
# to forbid it -- so the assertion is scoped to code and to the workflow.
if grep -rq 'CAVE_API_KEY\|CAVE_GATEWAY\|caveman wrap' \
     "$LEOHOME/core" "$LEOHOME/templates/workflow.md" 2>/dev/null; then
  bad "leo's code never reaches for the caveman gateway"
else
  ok "leo's code never reaches for the caveman gateway"
fi
# ...and the doc forbids it rather than merely omitting it.
has "$(cat "$LEOHOME/templates/tools/caveman.md")" "no .CAVE_API_KEY" \
  "the caveman doc rules the gateway out explicitly"

printf "commit is the human's\n"
# In a subshell, so the assertion holds whatever the caller's environment is:
# this test is about leo's behaviour, not about whether LEO_YES happens to be
# set in the shell that ran the suite.
out=$(unset LEO_YES; NO_COLOR=1 "$LEO" commit "x" </dev/null 2>&1); rc=$?
has "$out" "needs a human at a terminal" "commit refuses without a tty"
[ "$rc" = 2 ] && ok "commit exits 2 when refused" || bad "commit exit was $rc, wanted 2"


printf 'the build makes one file that behaves like the source tree\n'
# --out keeps the suite from writing dist/ into the developer's own clone.
BUNDLE="$TMP/leo-bundle"
out=$(NO_COLOR=1 "$LEO" build --out "$BUNDLE" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "leo build exits 0" || bad "leo build exit was $rc: $out"
[ -x "$BUNDLE" ] && ok "the bundle is executable" || bad "the bundle is executable"

# The property that makes it a bundle rather than a launcher: it sits outside
# the source tree, so LEO_HOME resolves to a directory with no core/ in it. If
# anything still reaches for $LEO_HOME/<file>, every assertion below dies here.
sv=$(NO_COLOR=1 "$LEO" --version 2>&1)
bv=$(NO_COLOR=1 "$BUNDLE" --version 2>&1)
[ "$sv" = "$bv" ] && ok "the bundle reports the source version ($sv)" \
                  || bad "version: source=$sv bundle=$bv"

out=$(NO_COLOR=1 "$BUNDLE" help 2>&1)
has "$out" "COMMANDS" "the bundle prints help"

# A bundle that cannot be read is a binary, and leo's comments are its docs.
# One comment from lib.sh and one from a command, so the assertion covers both
# things the build compiles in. Not the entrypoint's -- the bundle replaces
# that file with a preamble of its own, on purpose.
for c in "in one file you can read in a minute" "The plan is the yardstick"; do
  grep -q "$c" "$BUNDLE" && ok "the bundle keeps its comments ($c)" \
                         || bad "the bundle dropped a comment ($c)"
done

printf 'the bundle and the source tree init a repo identically\n'
newrepo() { # newrepo <dir> -- a repo at the same starting point every time
  mkdir -p "$1" && ( cd "$1" && git init -q . \
    && git config user.email t@t && git config user.name t \
    && echo one > f.txt && git add -A && git commit -qm init ) >/dev/null 2>&1
}
newrepo "$TMP/s-repo"; newrepo "$TMP/b-repo"
( cd "$TMP/s-repo" && NO_COLOR=1 "$LEO"    init ) >/dev/null 2>&1
( cd "$TMP/b-repo" && NO_COLOR=1 "$BUNDLE" init ) >/dev/null 2>&1

# Byte for byte, or the bundle is a fork rather than a build. This is the
# wrong-change signal from the plan, written as an assertion.
d=$(diff -r -x '.git' "$TMP/s-repo" "$TMP/b-repo" 2>&1)
[ -z "$d" ] && ok "init output is identical" || bad "init output differs: $d"

# Named individually too: a diff of two empty trees also passes.
for f in AGENTS.md CLAUDE.md .leo/workflow.md .leo/config .leo/tools/serena.md; do
  [ -f "$TMP/b-repo/$f" ] && ok "the bundle installs $f" \
                          || bad "the bundle installs $f"
done

printf 'the bundle keeps every seam the source tree has\n'
cd "$TMP/b-repo"
printf 'TEST_CMD="true"\n' >> .leo/config
git add -A && git commit -qm adopt >/dev/null 2>&1
echo two >> f.txt

out=$(NO_COLOR=1 "$BUNDLE" plan "bundled" 2>&1)
has "$out" "plan created" "the bundle writes a plan"
# task.md is a template too, and it is read through a different call site than
# init's -- so it gets its own assertion rather than riding on init's.
printf '# Plan: x\n\n| T1 | a | b | 5 | pending |\n\nest: 20 LOC\n' > .leo/plan.md
out=$(NO_COLOR=1 "$BUNDLE" task T1 2>&1)
has "$out" "T1" "the bundle writes a task file from the embedded template"

out=$(NO_COLOR=1 "$BUNDLE" session --mode coding 2>&1)
has "$out" "Serena" "the bundle knows its built-in adapters"

# ...and still loads the ones a repository adds, which is the half of adapter
# loading a bundle is most likely to drop on the floor.
mkdir -p .leo/integrations
cat > .leo/integrations/zzdemo.sh <<'ADAPTER'
zzdemo_present() { command -v zzdemo-not-real >/dev/null 2>&1; }
zzdemo_label()   { printf 'ZZ Demo'; }
zzdemo_hint()    { say "not a real tool"; }
zzdemo_default() { case "$1" in review) printf 'on' ;; *) printf 'off' ;; esac; }
ADAPTER
out=$(NO_COLOR=1 "$BUNDLE" session --mode review 2>&1)
has "$out" "ZZ Demo  *ON" "the bundle loads a repository's own adapter"

out=$(NO_COLOR=1 "$BUNDLE" scan 2>&1); rc=$?
[ "$rc" = 0 ] && ok "the bundle scans" || bad "the bundle scan exit was $rc"
# `grep -qc .` is true even for empty input, which would have made this pass
# against a bundle that printed nothing. Count the lines, as check() does.
out=$(NO_COLOR=1 "$BUNDLE" check 2>&1)
n=$(printf '%s' "$out" | grep -c .)
[ "$n" -ge 4 ] && ok "the bundle checks" || bad "the bundle check printed $n lines"

# commit re-execs leo to run the checks. In the source tree that is
# $LEO_HOME/leo; in a bundle it has to be the bundle itself.
out=$(unset LEO_YES; NO_COLOR=1 "$BUNDLE" commit "x" </dev/null 2>&1); rc=$?
has "$out" "needs a human at a terminal" "the bundle's commit refuses without a tty"
[ "$rc" = 2 ] && ok "the bundle's commit exits 2" || bad "bundle commit exit was $rc"
cd "$TMP/repo"

printf 'the grill is vendored, not paraphrased\n'
newrepo "$TMP/g-repo"
cd "$TMP/g-repo" && NO_COLOR=1 "$LEO" init >/dev/null 2>&1
for f in .leo/skills/grilling/SKILL.md .leo/skills/grill-me/SKILL.md .leo/skills/LICENSE; do
  [ -f "$f" ] && ok "init installs $f" || bad "init installs $f"
done
# Verbatim, not reworded. These are the load-bearing phrases: if leo ever grows
# its own dialect of the grill, one of these stops matching.
g=$(cat .leo/skills/grilling/SKILL.md 2>/dev/null || true)
has "$g" "frontier"                        "the vendored grill keeps the frontier"
has "$g" "design tree"                     "the vendored grill keeps the design tree"
has "$g" "Do not act on it until the user" "the vendored grill keeps its stop condition"
has "$g" "sub-agent"                       "the vendored grill keeps fact-finding off the user"
# MIT requires the notice to travel with the copy.
has "$(cat .leo/skills/LICENSE)" "Matt Pocock" "the upstream copyright travels with it"

printf 'every task is grilled, and the check has teeth\n'
printf 'TEST_CMD="true"\n' >> .leo/config
git add -A && git commit -qm adopt >/dev/null 2>&1
printf '# Plan: x\n\n| #  | Task | Files | Est LOC | Status |\n|--|--|--|--|--|\n| T1 | a | f.txt | 5 | in-progress |\n\nest: 50 LOC\n' > .leo/plan.md
NO_COLOR=1 "$LEO" task T1 >/dev/null 2>&1
t=$(cat .leo/tasks/T1.md 2>/dev/null || true)
has "$t" "## Grill"      "a task file has a Grill section"
has "$t" "leo:ungrilled" "a fresh task file is marked ungrilled"

# The whole point: an ungrilled task must fail the check, not warn.
out=$(NO_COLOR=1 "$LEO" check 2>&1); rc=$?
has "$out" "ungrilled" "check names the ungrilled task"
[ "$rc" = 1 ] && ok "check fails on an ungrilled task" \
              || bad "check exit was $rc on an ungrilled task, wanted 1"

# ...and passes once the grill is recorded. Same file, one edit.
grep -v 'leo:ungrilled' .leo/tasks/T1.md > "$TMP/t1" && mv "$TMP/t1" .leo/tasks/T1.md
out=$(NO_COLOR=1 "$LEO" check 2>&1)
printf '%s' "$out" | grep -q "ungrilled" \
  && bad "check stops complaining once grilled" || ok "check stops complaining once grilled"

printf 'subtasks live inside their parent, and are grilled too\n'
NO_COLOR=1 "$LEO" task T1 --sub "first subtask" >/dev/null 2>&1
NO_COLOR=1 "$LEO" task T1 --sub "second subtask" >/dev/null 2>&1
t=$(cat .leo/tasks/T1.md)
has "$t" "## T1.1 first subtask"  "the first subtask is a heading in the parent"
has "$t" "## T1.2 second subtask" "subtasks number themselves"
# One file per task is the whole storage argument. If a subtask ever gets its
# own file, a five-task change becomes twenty files.
[ ! -f .leo/tasks/T1.1.md ] && ok "a subtask gets no file of its own" \
                            || bad "a subtask gets no file of its own"
# A subtask carries its own grill, or "grill every task" is a slogan.
n=$(grep -c 'leo:ungrilled' .leo/tasks/T1.md || true)
[ "$n" = 2 ] && ok "each subtask arrives ungrilled" \
             || bad "expected 2 ungrilled subtasks, found $n"
out=$(NO_COLOR=1 "$LEO" check 2>&1); rc=$?
[ "$rc" = 1 ] && ok "an ungrilled subtask fails the check too" \
              || bad "ungrilled subtask check exit was $rc, wanted 1"

printf 'AGENTS.md binds, and repo detail lives elsewhere\n'
[ -f CONTEXT.md ] && ok "init installs CONTEXT.md" || bad "init installs CONTEXT.md"
a=$(cat AGENTS.md)
has "$a" "grill"    "AGENTS.md names the grill"
has "$a" "CONTEXT"  "AGENTS.md points at CONTEXT.md"
# It loads on every request of every session. A weak model skims a long file,
# which is the failure this whole change exists to fix.
n=$(wc -l < AGENTS.md | tr -d ' ')
[ "$n" -le 50 ] && ok "AGENTS.md is $n lines (<= 50)" \
                || bad "AGENTS.md is $n lines, over the 50-line budget"
cd "$TMP/repo"

printf 'the benchmark exists, and never runs itself\n'
[ -f "$LEOHOME/t/bench.sh" ] && ok "t/bench.sh exists" || bad "t/bench.sh exists"
# No key, no network, no surprise spend: it has to say so and exit clean.
out=$(ANTHROPIC_API_KEY= NO_COLOR=1 bash "$LEOHOME/t/bench.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "the benchmark exits 0 with no key" || bad "benchmark exit was $rc"
has "$out" "ANTHROPIC_API_KEY" "the benchmark says why it skipped"
# It costs money and needs the network. Nothing may run it as a side effect.
grep -q 'bench' "$LEOHOME/core/cmd/check.sh" \
  && bad "leo check never runs the benchmark" || ok "leo check never runs the benchmark"

# The session benchmark reads transcripts Claude Code already wrote. No key, no
# network -- so unlike bench.sh it must work here and now.
[ -f "$LEOHOME/t/bench-session.sh" ] && ok "t/bench-session.sh exists" \
                                     || bad "t/bench-session.sh exists"
out=$(NO_COLOR=1 bash "$LEOHOME/t/bench-session.sh" "$TMP/nope-not-a-project" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "the session benchmark exits 0 with no transcripts" \
              || bad "session benchmark exit was $rc"
has "$out" "no transcripts" "the session benchmark says when it has no data"
# It reads private transcripts. It must never post them anywhere.
grep -qE 'curl|wget|api\.anthropic' "$LEOHOME/t/bench-session.sh" \
  && bad "the session benchmark makes no network call" \
  || ok "the session benchmark makes no network call"

# The footprint benchmark measures what the always-loaded files cost. It must
# run anywhere, since it is the one that can see a change made this morning.
out=$(NO_COLOR=1 bash "$LEOHOME/t/bench-context.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "the footprint benchmark runs" || bad "footprint exit was $rc"
has "$out" "ALWAYS LOADED" "the footprint benchmark separates loaded from on-demand"
grep -qE 'curl|wget|api\.anthropic' "$LEOHOME/t/bench-context.sh" \
  && bad "the footprint benchmark makes no network call" \
  || ok "the footprint benchmark makes no network call"

printf 'the session points at tool docs, it never prints them\n'
cd "$TMP/g-repo"
out=$(NO_COLOR=1 "$LEO" session --mode coding 2>&1)
has "$out" "instructions: .leo/tools/serena.md" "the session prints the doc path"
# The cost control: seven tool docs are 11KB. Printing one into the session
# output would put it in context for a session that may never use the tool.
printf '%s' "$out" | grep -q "find_referencing_symbols" \
  && bad "the session never inlines a tool doc" \
  || ok "the session never inlines a tool doc"
cd "$TMP/repo"

printf 'a passing check says little; a failing one says everything\n'
cd "$TMP/g-repo"
# Success is the common case and prints the least useful information, and
# every line of it is re-read on every turn for the rest of the session.
# Clean slate: this repo still holds the ungrilled subtasks the grill block
# left behind, and a check failing for that reason would look like a terse-
# output failure here.
rm -f .leo/plan.md .leo/manifest.md .leo/tasks/*.md
printf '# Plan: x\n\n| T1 | a | b | 5 | pending |\n\nest: 90 LOC\n' > .leo/plan.md
out=$(NO_COLOR=1 "$LEO" check 2>&1); rc=$?
n=$(printf '%s' "$out" | grep -c .)
[ "$rc" = 0 ] && ok "terse check still exits 0" || bad "terse check exit was $rc"
[ "$n" -le 8 ] && ok "a passing check prints $n lines (<= 8)" \
               || bad "a passing check printed $n lines, wanted <= 8"
# It must still say the things a person needs: that it passed, and against what.
has "$out" "passed" "the terse check still says it passed"

# --verbose brings back every stage, for when you need to see the working.
out=$(NO_COLOR=1 "$LEO" check --verbose 2>&1)
v=$(printf '%s' "$out" | grep -c .)
[ "$v" -gt "$n" ] && ok "--verbose prints more ($v lines) than terse ($n)" \
                  || bad "--verbose printed $v lines, terse printed $n"
has "$out" "rules"  "--verbose names the rules stage"
has "$out" "budget" "--verbose names the budget stage"

# A failure is rare and the detail is the entire point. It must not be terse.
printf 'nope\n' > .leo/rules/BREAKME.md
printf '\n## Verify\n\n```sh\nexit 1\n```\n' >> .leo/rules/BREAKME.md
out=$(NO_COLOR=1 "$LEO" check 2>&1); rc=$?
f=$(printf '%s' "$out" | grep -c .)
[ "$rc" = 1 ] && ok "a failing check still fails" || bad "failing check exit was $rc"
[ "$f" -gt 4 ] && ok "a failing check stays loud ($f lines)" \
               || bad "a failing check printed only $f lines"
has "$out" "BREAKME" "a failing check names what failed"
rm -f .leo/rules/BREAKME.md

printf 'leo says when to end the session, where it can actually tell\n'
# Quadratic cost: every turn re-reads every turn before it, so the cheapest
# thing leo can do is tell you to stop. It fires where leo can see agent-
# agnostically -- a commit landing -- not on a turn count it cannot observe.
has "$(cat "$LEOHOME/core/cmd/commit.sh")" "fresh session" \
  "commit suggests a fresh session for the next task"
# ...and it must not have been done by reading Claude Code's transcripts.
grep -qE 'CLAUDE_CODE_SESSION_ID|\.claude/projects' "$LEOHOME/core/cmd/commit.sh" \
     "$LEOHOME/core/cmd/check.sh" "$LEOHOME/core/lib.sh" "$LEOHOME/core/cmd/task.sh" \
  && bad "leo stays agent-agnostic" || ok "leo stays agent-agnostic"

# The instruction is short and must be seen; the reasoning is long and must not
# be paid for on every request.
has "$(cat "$LEOHOME/templates/AGENTS.md")" "fresh session" \
  "AGENTS.md carries the instruction"
w=$(grep -ci "quadratic\|re-read" "$LEOHOME/templates/AGENTS.md" || true)
[ "${w:-0}" -eq 0 ] && ok "AGENTS.md does not carry the reasoning" \
                    || bad "the reasoning leaked into the always-loaded file"
has "$(cat "$LEOHOME/templates/workflow.md")" "fresh session" \
  "workflow.md carries the reasoning"
cd "$TMP/repo"

printf 'the grill has a floor and no ceiling\n'
# leo says WHEN to grill. How much to grill is the vendored skill's business,
# and it stops on shared understanding rather than on a count. Any number leo
# states here is leo overriding the thing it vendored.
for f in templates/workflow.md templates/AGENTS.md templates/task.md \
         core/cmd/check.sh README.md; do
  if grep -nE '[0-9]+ *[-–] *[0-9]+ *questions|earns one question|one question is fine|ask [0-9]+ (to|-|–) *[0-9]* *questions' \
       "$LEOHOME/$f" >/dev/null 2>&1; then
    bad "no question cap in $f"
  else
    ok "no question cap in $f"
  fi
done

# The floor is not a number, and it must survive: zero questions is not a grill.
has "$(cat "$LEOHOME/templates/workflow.md")" "shared understanding" \
  "the workflow names the real stop condition"
has "$(cat "$LEOHOME/core/cmd/check.sh")" "ungrilled" \
  "check still fails on an ungrilled task"

# The vendored skill is somebody else's file. Editing it to make a point about
# question counts would defeat the reason it was vendored.
g="$LEOHOME/templates/skills/grilling/SKILL.md"
has "$(cat "$g")" "frontier"     "the vendored skill is still intact"
has "$(cat "$g")" "Do not act on it until the user confirms" \
  "the vendored stop condition is untouched"
n=$(wc -c < "$g" | tr -d ' ')
[ "$n" -eq 1987 ] && ok "the vendored skill is byte-for-byte unchanged ($n b)" \
                  || bad "the vendored skill changed size: $n b, expected 1987"

printf 'the documents describe the tool that exists\n'
# A document showing output the tool no longer produces teaches the reader
# their install is broken. These are the four things that changed under DEMO.
d="$LEOHOME/DEMO.md"
# Patterns are anchored on a leading word rather than starting with "--",
# because grep reads a leading double dash as the end of its own options.
has "$(cat "$d")" "grill"           "DEMO names the grill"
has "$(cat "$d")" "task T1 --sub"   "DEMO names subtasks"
has "$(cat "$d")" "ungrilled"       "DEMO names the gate that blocks"
has "$(cat "$d")" "check --verbose" "DEMO names the verbose flag"

# Every `leo check` block in DEMO must show the grill stage, because every real
# run prints one between manifest and budget.
n_blocks=$(grep -c '^manifest$' "$d" || true)
n_grill=$(grep -c '^grill$' "$d" || true)
[ "${n_grill:-0}" -ge "${n_blocks:-0}" ] \
  && ok "every check block in DEMO shows the grill stage ($n_grill/$n_blocks)" \
  || bad "DEMO has $n_blocks check blocks but only $n_grill grill stages"

# README is where someone looks first, so the loop it prints must be the loop.
r="$LEOHOME/README.md"
has "$(cat "$r")" "subtask" "README names the subtask stage"
for c in "leo plan" "leo task" "leo scan" "leo check" "leo commit" "leo build" \
         "leo review"; do
  has "$(cat "$r")" "$c" "README names $c"
done
printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
