#!/usr/bin/env bash
# Smoke test: drive the real CLI through a real repository.
#
# Its main job is the boring one -- proving that `leo check` still SAYS
# something in every combination of missing plan and missing manifest. Under
# `set -e` with `pipefail`, one grep that legitimately matches nothing is enough
# to kill the command mid-run and print nothing at all, which looks exactly like
# success to a script and exactly like a hang to a person.

set -u
LEO=$(cd -P "$(dirname "$0")/.." && pwd)/leo
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
has "$out" "Code graph  *no adapter" "a capability leo cannot detect says so, not MISSING"

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

printf "commit is the human's\n"
# In a subshell, so the assertion holds whatever the caller's environment is:
# this test is about leo's behaviour, not about whether LEO_YES happens to be
# set in the shell that ran the suite.
out=$(unset LEO_YES; NO_COLOR=1 "$LEO" commit "x" </dev/null 2>&1); rc=$?
has "$out" "needs a human at a terminal" "commit refuses without a tty"
[ "$rc" = 2 ] && ok "commit exits 2 when refused" || bad "commit exit was $rc, wanted 2"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
