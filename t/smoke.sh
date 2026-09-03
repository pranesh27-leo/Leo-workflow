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

printf "commit is the human's\n"
out=$(NO_COLOR=1 "$LEO" commit "x" </dev/null 2>&1); rc=$?
has "$out" "needs a human at a terminal" "commit refuses without a tty"
[ "$rc" = 2 ] && ok "commit exits 2 when refused" || bad "commit exit was $rc, wanted 2"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
