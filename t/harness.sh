#!/usr/bin/env bash
# The harness, checked.
#
# There is no program to test any more, so most of what the old suite did has
# nothing left to assert. What is left is the two things that can still be
# wrong, and both of them are silent:
#
#   the copier    ships a file it does not have, or overwrites work
#   the documents contradict each other, or point at a path that is not there
#
# The second is the one that matters. A harness is a set of files that refer
# to each other by path, and a dangling pointer teaches the agent nothing
# while looking exactly like an instruction. That is the failure this whole
# thing exists to avoid, so it is the failure most worth a test.

set -u
HOME_DIR=$(cd -P "$(dirname "$0")/.." && pwd)
LEO="$HOME_DIR/bin/leo.js"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/leo-h.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

# =========================================================================
printf '\nthe copier\n'
# =========================================================================
R="$TMP/repo"; mkdir -p "$R" && cd "$R"

out=$(node "$LEO" init 2>&1); rc=$?
[ "$rc" = 0 ] && ok "leo init exits 0" || bad "leo init exit was $rc: $out"

# Every file the harness names, present after one run. Listed here and not
# derived from the source tree: a test that reads the same list as the code
# passes when both are wrong together.
for f in AGENTS.md \
         .agents/leo.md \
         .agents/tools/graph.md \
         .agents/tools/rtk.md \
         .agents/skills/grill-me/SKILL.md \
         .agents/skills/tdd/SKILL.md \
         .agents/skills/ponytail/SKILL.md \
         .agents/skills/humanizer/SKILL.md \
         .agents/skills/feynman/SKILL.md \
         .agents/skills/evidence/SKILL.md \
         .agents/skills/points/SKILL.md \
         .agents/skills/replan/SKILL.md \
         .agents/skills/asd-ste100/SKILL.md \
         .agents/skills/asd-ste100/references/writing-rules.md \
         .agents/skills/asd-ste100/examples/before-after.md \
         .agents/skills/asd-ste100/scripts/ste-lint.py \
         .agents/tools/understand.md \
         .claude/skills/grill-me/SKILL.md \
         .claude/skills/tdd/SKILL.md \
         .claude/skills/ponytail/SKILL.md \
         .claude/skills/humanizer/SKILL.md \
         .claude/skills/feynman/SKILL.md \
         .claude/skills/evidence/SKILL.md \
         .claude/skills/points/SKILL.md \
         .claude/skills/replan/SKILL.md \
         .claude/skills/asd-ste100/SKILL.md \
         .claude/skills/asd-ste100/scripts/ste-lint.py; do
  [ -f "$f" ] && ok "init writes $f" || bad "init did not write $f"
done

# The templates, and the three repository documents. A stage that says "copy
# the template" and no template is a dangling instruction -- the exact
# failure the pointer check below exists for, arriving through the copier
# instead of through the prose.
for f in .agents/templates/goal.md \
         .agents/templates/plan.md \
         .agents/templates/task.md \
         .agents/templates/manifest.md \
         .agents/templates/review.md \
         CONTEXT.md ARCHITECTURE.md RULES.md; do
  [ -f "$f" ] && ok "init writes $f" || bad "init did not write $f"
done

# The templates are instructions; the files they produce are work. Shipping
# a filled-in .agents/plan.md would be shipping half a change, and the
# pointer check below asserts the same thing from the other side.
for f in .agents/goals .agents/plan.md; do
  [ -e "$f" ] && bad "init pre-made $f — that is the agent's to write" \
               || ok "init does not pre-make $f"
done

# Vendored work travels with its own licence, in its own directory. One
# LICENSE at the top for five skills from three authors leaves a reader
# guessing which terms cover what.
for s in grill-me ponytail humanizer asd-ste100; do
  [ -f ".agents/skills/$s/LICENSE" ] \
    && ok "$s ships the licence it is used under" \
    || bad "$s is vendored with no licence beside it"
done

# Running it twice must not touch a repository somebody has since edited.
printf 'MY OWN NOTES\n' >> AGENTS.md
node "$LEO" init >/dev/null 2>&1
grep -q 'MY OWN NOTES' AGENTS.md \
  && ok "a second init keeps what the developer wrote" \
  || bad "a second init overwrote AGENTS.md"

node "$LEO" init --force >/dev/null 2>&1
grep -q 'MY OWN NOTES' AGENTS.md \
  && bad "--force did not overwrite" \
  || ok "--force overwrites, which is what it is for"

# An unknown command must not look like success. An agent that runs
# `leo check` out of habit has to see a failure, not silence.
node "$LEO" check >/dev/null 2>&1
[ "$?" = 1 ] && ok "an unknown command exits 1" || bad "unknown command did not exit 1"
node "$LEO" >/dev/null 2>&1
[ "$?" = 0 ] && ok "bare leo prints usage and exits 0" || bad "bare leo did not exit 0"

cd "$HOME_DIR"

# =========================================================================
printf '\nevery path the documents name actually exists\n'
# =========================================================================
# The dangling-pointer check. Each document is read for the paths it tells an
# agent to open, and every one has to be a file the copier installs.
# Two kinds of path, and the difference is the whole point. A path to an
# INSTRUCTION -- a skill, a tool file -- must exist the moment init finishes,
# or the agent is told to read something that is not there. A path to a WORK
# PRODUCT -- the plan, the manifest, a task file -- must NOT exist yet: those
# are what the agent writes as it goes, and shipping one would mean shipping
# a half-finished change.
#
# An earlier version of this test did not distinguish them and failed on
# .agents/plan.md, which is correct behaviour being reported as a bug.
products='.agents/goals'

is_product() {
  for q in $products; do
    case "$1" in "$q"|"$q"/*) return 0 ;; esac
  done
  return 1
}

missing=""; premature=""
for doc in "$R/AGENTS.md" "$R/.agents/leo.md" "$R/.agents/tools/graph.md" \
           "$R/.agents/tools/rtk.md" "$R/.agents/skills/grill-me/SKILL.md"; do
  [ -f "$doc" ] || continue
  # Paths appear in backticks or bare. Drop trailing punctuation, and skip
  # the ones carrying a glob or a placeholder: `.agents/tools/<name>.md`
  # names a pattern, not a file.
  for p in $(grep -oE '\.agents/[A-Za-z0-9._/-]+' "$doc" | sort -u); do
    case "$p" in *'<'*|*'*'*) continue ;; esac
    p=${p%.}
    if is_product "$p"; then
      [ -e "$R/$p" ] && premature="$premature $p"
    else
      [ -e "$R/$p" ] || missing="$missing $(basename "$doc"):$p"
    fi
  done
done
[ -z "$missing" ] && ok "every instruction path the documents name is installed" \
                  || bad "dangling pointers:$missing"
[ -z "$premature" ] && ok "no work product ships pre-made" \
                    || bad "init shipped a file the agent is supposed to write:$premature"

# =========================================================================
printf '\nthe documents agree with each other\n'
# =========================================================================

# The stages, in one place. AGENTS.md names them in order; leo.md defines
# them. If AGENTS.md lists a stage leo.md never explains, the agent is told
# to do something with no instruction behind it.
for stage in goal understand grill plan task subtask build manifest review commit replan; do
  grep -qi "$stage" "$R/.agents/leo.md" \
    && ok "leo.md defines the $stage stage" \
    || bad "AGENTS.md names $stage and leo.md never explains it"
done

# The mode table and the skills that exist have to be the same set.
for skill in grill-me tdd ponytail humanizer feynman evidence points asd-ste100 replan; do
  grep -qi "$skill" "$R/AGENTS.md" \
    && ok "AGENTS.md maps $skill to modes" \
    || bad "$skill ships but AGENTS.md never says when to use it"
done
for tool in graph rtk understand; do
  grep -q ".agents/tools/$tool.md" "$R/AGENTS.md" \
    && ok "AGENTS.md names the $tool tool" \
    || bad "$tool ships but AGENTS.md never mentions it"
done

# Tools get the same treatment as skills: the rule for WHEN to reach for one
# lives in the always-loaded file, not only in the tool's own document. A
# pointer table says a tool exists; it does not make the agent use it, and
# the developer ends up typing "check the code graph for this" -- the
# instruction this harness exists to remove.
# The table HEADER, not the phrase anywhere -- the prose above it also says
# "reach for it", so a loose grep passed with the table reverted to a pointer
# list. Same failure as the per-reply check: guarding a sentence rather than
# a structure.
grep -qE '^\| *tool *\| *reach for it' "$R/AGENTS.md" \
  && ok "the tools table carries the rule, not just a pointer" \
  || bad "the tools table is a pointer list — using one is still a per-turn decision"

# And the moments are named in the stages themselves, so reaching for a tool
# is part of doing the stage rather than something remembered separately.
for moment in detect_changes trace_path; do
  grep -q "$moment" "$R/.agents/leo.md" \
    && ok "leo.md names $moment at the stage that wants it" \
    || bad "leo.md never says where $moment fits in the loop"
done

# Missing tools must be reported once, not every turn. A fact that has not
# changed since the last reply is noise on this one.
# "once" appears all over this file -- the developer configures the session
# once, a grill runs once per task. The rule being guarded is specifically
# about not repeating a missing tool, so match that sentence.
grep -qE 'once.*first time you would have used it' "$R/AGENTS.md" \
  && ok "AGENTS.md says to report a missing tool once, not repeatedly" \
  || bad "nothing stops a missing tool being announced every reply"

# Every template the documents tell the agent to copy must be a file the
# copier ships. This is the same dangling-pointer failure as a missing skill,
# one indirection further along.
for t in goal plan task manifest review; do
  grep -q "templates/$t.md" "$R/.agents/leo.md" \
    && ok "leo.md points at the $t template" \
    || bad "leo.md never tells the agent where to get the $t template"
done

# Announcing what is in use. The whole switch mechanism rests on it: a skill
# the developer can see being used is one they can object to, and one used
# silently is indistinguishable from one not used at all.
# Both halves of the TDD switch must exist, or the block at the top of
# AGENTS.md asks a question whose answer changes nothing.
grep -q 'TDD:' "$R/AGENTS.md" \
  && ok "AGENTS.md has the TDD line the developer sets" \
  || bad "no TDD line — the session block asks nothing"
grep -q 'TDD: yes' "$R/.agents/leo.md" && grep -q 'TDD: no' "$R/.agents/leo.md" \
  && ok "leo.md branches on both TDD answers" \
  || bad "leo.md does not define both TDD paths"

# The stages that are the developer's must say so where the agent reads them.
# This is the whole safety property: an agent that commits has taken a
# decision that was not its to take.
grep -q "developer's" "$R/.agents/leo.md" \
  && ok "leo.md marks the stages that are not the agent's" \
  || bad "leo.md never says which stages the agent must not do"
# Read the standing-orders section, not the whole file, and not a fixed
# sentence. The orders are a table now; grepping for the literal phrase
# "never commit" passed only while they happened to be written as prose, and
# a test that breaks on reformatting is testing the format rather than the
# rule.
orders=$(awk '/^## Standing orders/{f=1} f' "$R/AGENTS.md")
printf '%s' "$orders" | grep -qi 'never' \
  && ok "AGENTS.md has a standing-orders section of prohibitions" \
  || bad "AGENTS.md has no standing orders"
# The table ROW, not the word anywhere in the section. "After a commit, tell
# them to start a fresh session" sits in the same section and contains
# "commit", so a loose grep passed with the prohibition deleted -- the guard
# reported a rule that was no longer there.
for forbidden in commit install; do
  printf '%s' "$orders" | grep -qE "^\| *$forbidden *\|" \
    && ok "standing orders forbid $forbidden" \
    || bad "standing orders have no row forbidding $forbidden"
done

# The standing-order ROW, not a sentence in the prose. The prose gets
# reworded; the row is structural, and it is the same anchor the commit and
# install prohibitions use. A test tied to a phrase fails on a rewrite that
# strengthened the rule, which is what this one did.
printf '%s' "$orders" | grep -qE "^\| *use a skill or tool silently *\|" \
  && ok "standing orders forbid using a skill or tool silently" \
  || bad "nothing forbids using a skill or tool silently"

# evidence and points are not per-mode: they are in force on every reply, in
# every mode. The table ROW of each, with ON in all five mode columns -- a
# loose grep for the name would pass with one mode quietly set to OFF.
for skill in evidence points; do
  modes=$(awk '/^\| mode \|/{f=1;next} f&&/^\|---/{next} f&&/^\| \*\*/{print} f&&!/^\|/{exit}' "$R/AGENTS.md")
  col=$(awk '/^\| mode \|/{n=split($0,h,"|"); for(i=1;i<=n;i++){gsub(/ /,"",h[i]); if(h[i]=="'"$skill"'") print i}; exit}' "$R/AGENTS.md")
  offs=$(printf '%s\n' "$modes" | awk -F'|' -v c="$col" '{v=$c; gsub(/[ *]/,"",v); if (v!="ON") print}')
  [ -n "$col" ] && [ -z "$offs" ] && [ "$(printf '%s\n' "$modes" | grep -c .)" = 5 ] \
    && ok "$skill is ON in every mode" || bad "$skill is not ON in every mode"
done

# One reply style, not four. caveman said what points already says, so it
# is gone; a removed skill that still ships is one an agent can still load.
[ -e "$R/.agents/skills/caveman" ] || [ -e "$R/.claude/skills/caveman" ] \
  && bad "caveman still ships after it was folded into points" \
  || ok "caveman is not shipped"
grep -qi 'caveman' "$R/AGENTS.md" \
  && bad "AGENTS.md still names caveman" || ok "AGENTS.md no longer names caveman"

# points is the one style, built from three skills, two lines a point.
pts="$R/.agents/skills/points/SKILL.md"
for src in feynman humanizer asd-ste100; do
  grep -q "skills/$src/SKILL.md" "$pts" \
    && ok "points takes from $src" || bad "points does not say what it takes from $src"
done
grep -qiE 'at most two lines' "$pts" \
  && ok "points caps a point at two lines" || bad "points has no two-line cap"

# Contradictions found in review. Each was a sentence the file then broke.
grep -q 'There is no third state' "$R/AGENTS.md" \
  && bad "AGENTS.md says there is no third state, then lists one" \
  || ok "AGENTS.md does not deny the on-request state it uses"
grep -qi 'one word for one thing' "$R/AGENTS.md" "$pts" \
  && bad "the STE line keeps a rule the STE skill drops for prose" \
  || ok "no line asks for the STE rule its own skill drops for prose"
grep -qE '`:1`' "$R/.agents/skills/evidence/SKILL.md" \
  && bad "evidence suggests :1, a citation that always passes" \
  || ok "evidence does not suggest a ritual :1 citation"

# feynman in full is long form, and long form is only on request. ON in a
# mode would make every reply in it long and points would never apply.
fcol=$(awk '/^\| mode \|/{n=split($0,h,"|"); for(i=1;i<=n;i++){gsub(/ /,"",h[i]); if(h[i]=="feynman") print i}; exit}' "$R/AGENTS.md")
fvals=$(awk -F'|' -v c="$fcol" '/^\| \*\*(coding|debugging|learning|review|exploration)\*\* \|/{v=$c; gsub(/^ +| +$/,"",v); print v}' "$R/AGENTS.md" | sort -u)
[ -n "$fcol" ] && [ "$fvals" = "on request" ] \
  && ok "feynman in full is on request in every mode" || bad "feynman is not on request in every mode: $fvals"

# The header lists what is not the default. Listing the always-on skills on
# every reply says nothing the developer does not already know.
grep -q 'State which skills are in force' "$R/AGENTS.md" \
  && bad "every reply still lists every skill in force" \
  || ok "the header names only what is not the default"

# The goal loop. Each rule below was asked for by the developer, and each is
# guarded by the structure that carries it, not by a word that happens to
# appear somewhere in the file.
L="$R/.agents/leo.md"
grep -qE '^#+ .*Create a goal' "$R/AGENTS.md" \
  && ok "AGENTS.md has a section that asks whether to create a goal" \
  || bad "nothing asks the developer whether to create a goal"
grep -q 'Create a goal for this?' "$R/AGENTS.md" \
  && ok "the goal question is written out word for word" || bad "the goal question is not written out"
grep -qi 'green signal' "$L" \
  && ok "leo.md waits for the developer's green signal before the commit message" \
  || bad "leo.md drafts the commit message without a green signal"
grep -qiE '^#+ .*cycle two' "$L" "$R/AGENTS.md" \
  && bad "cycle two is still a section, after the review replaced it" \
  || ok "cycle two is gone; the review before commit replaced it"
grep -q '▶ Working on' "$R/AGENTS.md" && grep -q '✓ Done' "$R/AGENTS.md" \
  && ok "AGENTS.md defines the start line and the done lines" \
  || bad "AGENTS.md has no progress line format"
grep -q 'Noted:' "$R/AGENTS.md" \
  && ok "the done lines carry an observed note" || bad "the done lines have no observed note"
for row in 'guess' 'add a wrapper, helper or abstraction'; do
  printf '%s' "$orders" | grep -qE "^\| *$row" \
    && ok "standing orders forbid: $row" || bad "standing orders have no row: $row"
done
# No AI attribution in a commit message. The developer does not want it, so
# the template must not ask for one and a standing order must forbid it.
tmpl=$(awk '/Draft the message/{f=1} f&&/^```$/{n++; if(n==2) exit} f' "$L")
[ -n "$tmpl" ] && printf '%s' "$tmpl" | grep -qiE 'Assisted-by|Co-Authored-By|Generated with' \
  && bad "leo.md's commit template still asks for an AI attribution line" \
  || ok "leo.md's commit template has no AI attribution line"
printf '%s' "$orders" | grep -qE '^\| *add an AI attribution' \
  && ok "standing orders forbid AI attribution in commit messages" \
  || bad "nothing forbids Co-Authored-By or similar in commit messages"

# A plan change is grilled before it is made: a changed plan is new
# decisions, and a decision nobody grilled is one the agent guessed. The
# step, by its heading in the skill, and the method it points at.
rp="$R/.agents/skills/replan/SKILL.md"
grep -qE '^[0-9]+\. \*\*Grill the change' "$rp" && grep -q 'skills/grill-me/SKILL.md' "$rp" \
  && ok "replan grills the change before editing the plan" || bad "replan edits the plan without a grill"
grep -qi 'grill' <(grep '^| \*\*replan\*\*' "$R/AGENTS.md") \
  && ok "the replan rule in AGENTS.md says it grills" || bad "AGENTS.md's replan rule skips the grill"
grep -q '## Change log' "$R/.agents/templates/plan.md" \
  && ok "the plan template records changes made mid-way" || bad "a replan leaves no record in the plan"
grep -q 'Done when' "$R/.agents/templates/review.md" && grep -qi 'green signal' "$R/.agents/templates/review.md" \
  && ok "the review template checks each Done-when and ends at the green signal" \
  || bad "the review template does not check the goal"

# And the per-reply framing: the rules have to be in force on every request,
# not read once at the start of a session. That distinction is the whole
# difference between a harness and a README.
# The section HEADING, not the phrase anywhere. "every reply" also appears in
# the prose below it, so a loose grep passed with the heading rewritten back
# to a session-start ritual -- reporting a contract that was no longer there.
grep -qiE '^#+ .*every reply' "$R/AGENTS.md" \
  && ok "AGENTS.md's protocol is headed as per-reply, not per-session" \
  || bad "AGENTS.md reads as a session-start ritual, not a per-reply contract"


# =========================================================================
printf '\nthe vendored grill is untouched\n'
# =========================================================================
# It is somebody else's file under his licence. Byte-for-byte or it is not
# vendored, it is forked.
# Vendored byte-for-byte. A size that drifts means somebody edited someone
# else's file in place, which is a fork wearing a vendor's name.
for pair in "ponytail 6637" "humanizer 28728" "asd-ste100 16430"; do
  set -- $pair
  n=$(wc -c < "$R/.agents/skills/$1/SKILL.md" | tr -d ' ')
  [ "$n" = "$2" ] && ok "$1/SKILL.md is $2 bytes, as upstream" \
                  || bad "$1/SKILL.md is $n bytes, upstream is $2 — it has been edited"
done
grep -q 'Matt Pocock' "$R/.agents/skills/grill-me/LICENSE" \
  && ok "grill-me carries Matt Pocock's licence" \
  || bad "grill-me's licence is missing or wrong"
n=$(wc -c < "$R/.agents/skills/asd-ste100/scripts/ste-lint.py" | tr -d ' ')
[ "$n" = 181763 ] && ok "ste-lint.py is 181763 bytes, as upstream" \
                 || bad "ste-lint.py is $n bytes, upstream is 181763 — it has been edited"
grep -qi 'DietrichGebert' "$R/.agents/skills/ponytail/LICENSE" \
  && ok "ponytail carries its author's licence" \
  || bad "ponytail's licence is missing or wrong"
# grill-me IS modified, and says so. Claiming otherwise would misattribute a
# changed file to its author.
grep -qi 'adapted' "$R/.agents/skills/grill-me/SKILL.md" \
  && ok "grill-me says it is adapted, not copied" \
  || bad "grill-me is modified but does not say so"
# The INSTRUCTION must not be vendor-specific. The file may still mention
# the Skill tool while explaining what it changed and why -- that is
# attribution, not an instruction, and an earlier version of this test could
# not tell the two apart.
grep -qiE '^ *(call|use) the skill tool' "$R/.agents/skills/grill-me/SKILL.md" \
  && bad "grill-me instructs the reader to call Claude Code's Skill tool" \
  || ok "grill-me's instruction names a path, not one runtime's mechanism"

# =========================================================================
printf '\nthe evidence hook\n'
# =========================================================================
# The one thing in the harness that runs. It reads the reply the agent is
# about to finish with and sends it back if a cited line does not exist, or
# if it names a file in the repository and cites nothing. Both are checkable
# by a program, which is the point: the rule in AGENTS.md is advice, this is
# a gate.
HOOK="$R/.agents/hooks/check-evidence.js"
E="$TMP/ev"; mkdir -p "$E/src" "$E/.git"
printf 'one\ntwo\nthree\n' > "$E/src/app.js"

# Feed the hook a Stop payload; print BLOCK or PASS.
verdict() {
  out=$(printf '%s' "$1" | node "$HOOK" 2>/dev/null); rc=$?
  if [ "$rc" = 2 ] || printf '%s' "$out" | grep -q '"block"'; then echo BLOCK; else echo PASS; fi
}
payload() {  # message, [session], [stop_hook_active]
  node -e 'process.stdout.write(JSON.stringify({hook_event_name:"Stop",cwd:process.argv[1],session_id:process.argv[3]||"s",stop_hook_active:process.argv[4]==="1",last_assistant_message:process.argv[2]}))' "$E" "$1" "${2:-s$RANDOM}" "${3:-0}"
}

[ -f "$HOOK" ] && ok "init writes the evidence hook" || bad "init did not write .agents/hooks/check-evidence.js"
[ "$(verdict "$(payload 'It reads the config at `src/app.js:2`.')")" = PASS ] \
  && ok "a real file:line passes" || bad "a real file:line was blocked"
[ "$(verdict "$(payload 'See src/app.js:1-3 for the loop.')")" = PASS ] \
  && ok "a real line range passes" || bad "a real line range was blocked"
[ "$(verdict "$(payload 'It retries in `src/net.js:12`.')")" = BLOCK ] \
  && ok "a citation to a file that does not exist is sent back" || bad "a made-up file passed"
[ "$(verdict "$(payload 'It loops at `src/app.js:40`.')")" = BLOCK ] \
  && ok "a line past the end of the file is sent back" || bad "a line past EOF passed"
[ "$(verdict "$(payload 'The logic lives in `src/app.js` and runs first.')")" = BLOCK ] \
  && ok "naming a repo file with no line cited is sent back" || bad "an uncited claim about a repo file passed"
[ "$(verdict "$(payload 'Pushed. The release is up.')")" = PASS ] \
  && ok "a reply about no code passes" || bad "a reply with no code in it was blocked"
[ "$(verdict "$(payload 'Open http://localhost:3000 or example.com:443.')")" = PASS ] \
  && ok "URLs and host:port are not mistaken for citations" || bad "a URL was treated as a citation"
[ "$(verdict "$(payload 'It retries in `src/net.js:12`.' s 1)")" = PASS ] \
  && ok "a reply already sent back once is let through, so it cannot loop" || bad "stop_hook_active did not stop the loop"
# Claude Code's payload may not carry stop_hook_active, so the hook keeps its
# own count. Three blocks in a row on one session and it lets go.
for i in 1 2; do verdict "$(payload 'bad `src/net.js:1`' loop)" >/dev/null; done
[ "$(verdict "$(payload 'bad `src/net.js:1`' loop)")" = PASS ] \
  && ok "the hook gives up after two blocks on one session" || bad "the hook can block the same session forever"

# The reply it blocks has already been shown. Whatever the agent sends next
# is shown too, so the reason must ask for the corrections only -- not the
# whole reply again, which is the duplicate the developer then reads twice.
reason=$(printf '%s' "$(payload 'It retries in `src/net.js:12`.')" | node "$HOOK" 2>/dev/null)
printf '%s' "$reason" | grep -q 'Do not repeat' \
  && ok "a block asks for the corrections only, not the reply again" \
  || bad "a block makes the agent send the whole reply a second time"

# Real files, written the ways agents actually write them. Each of these was
# reported as missing while it sat on disk.
mkdir -p "$E/pkg/sub" "$TMP/sib/lib"
printf 'a\nb\n' > "$E/pkg/sub/mod.py"; printf 'x\n' > "$TMP/sib/lib/z.py"
[ "$(verdict "$(payload 'See `src\app.js:2`.')")" = PASS ] \
  && ok "a Windows backslash path to a real file passes" || bad "a backslash path to a real file was blocked"
[ "$(verdict "$(payload "See \`$E/src/app.js:3\`.")")" = PASS ] \
  && ok "an absolute path to a real file passes" || bad "an absolute path to a real file was blocked"
[ "$(verdict "$(payload 'See `sub/mod.py:2`.')")" = PASS ] \
  && ok "a path relative to a subdirectory of the workspace passes" || bad "a real file under a subdirectory was reported missing"
[ "$(verdict "$(payload 'See `../sib/lib/z.py:1`.')")" = PASS ] \
  && ok "a path into a sibling directory passes" || bad "a real file in a sibling directory was reported missing"
[ "$(verdict "$(payload "See \`$E/src/app.js:9\`.")")" = BLOCK ] \
  && ok "an absolute path past the end of the file is still sent back" || bad "absolute paths skip the line check"
printf '%s' "$reason" | grep -q "$E" \
  && ok "a missing file is reported with the directory it was looked for from" \
  || bad "a missing-file block does not say where it looked"

# Quotes. A citation followed by a quoted snippet is checked against the
# lines it names: an existing line with the wrong code on it is still a
# made-up citation.
[ "$(verdict "$(payload 'Defined at `src/app.js:2` `two`.')")" = PASS ] \
  && ok "a quote that is on the cited line passes" || bad "a correct quote was blocked"
[ "$(verdict "$(payload 'Defined at `src/app.js:2` `retry(3)`.')")" = BLOCK ] \
  && ok "a quote that is not on the cited line is sent back" || bad "a wrong quote passed"

# Giving up must be visible. A reply let through after two blocks looks the
# same as one that passed, unless the hook says so to the developer.
for i in 1 2; do verdict "$(payload 'bad `src/net.js:1`' giveup)" >/dev/null; done
gave=$(printf '%s' "$(payload 'bad `src/net.js:1`' giveup)" | node "$HOOK" 2>/dev/null)
printf '%s' "$gave" | grep -q '"systemMessage"' && ! printf '%s' "$gave" | grep -q '"block"' \
  && ok "when the hook gives up it warns the developer" || bad "the hook gives up silently"
act=$(printf '%s' "$(payload 'bad `src/net.js:1`' s 1)" | node "$HOOK" 2>/dev/null)
printf '%s' "$act" | grep -q '"systemMessage"' \
  && ok "a retry let through by stop_hook_active still warns" || bad "stop_hook_active lets bad citations through silently"

for f in .claude/settings.json .codex/hooks.json; do
  grep -q 'check-evidence.js' "$R/$f" 2>/dev/null \
    && ok "$f registers the evidence hook on Stop" || bad "$f does not register the hook"
done

# =========================================================================
printf '\nwhat npm would ship\n'
# =========================================================================
cd "$HOME_DIR"
listing=$(npm pack --dry-run 2>&1 || true)
for f in bin/leo.js .agents/AGENTS.md .agents/leo.md \
         .agents/skills/grill-me/SKILL.md .agents/skills/humanizer/SKILL.md \
         .agents/skills/ponytail/LICENSE .agents/tools/rtk.md; do
  printf '%s' "$listing" | grep -q "$f" \
    && ok "npm ships $f" \
    || bad "npm would drop $f"
done
v=$(node -e 'console.log(require("./package.json").version)')
[ "$v" = "$(cat VERSION | tr -d ' \n')" ] \
  && ok "package.json and VERSION agree ($v)" \
  || bad "package.json says $v, VERSION says $(cat VERSION)"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
