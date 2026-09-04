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

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
