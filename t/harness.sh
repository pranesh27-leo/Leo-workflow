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
         .agents/skills/caveman/SKILL.md \
         .agents/skills/humanizer/SKILL.md \
         .claude/skills/grill-me/SKILL.md \
         .claude/skills/tdd/SKILL.md \
         .claude/skills/ponytail/SKILL.md \
         .claude/skills/caveman/SKILL.md \
         .claude/skills/humanizer/SKILL.md; do
  [ -f "$f" ] && ok "init writes $f" || bad "init did not write $f"
done

# The templates, and the three repository documents. A stage that says "copy
# the template" and no template is a dangling instruction -- the exact
# failure the pointer check below exists for, arriving through the copier
# instead of through the prose.
for f in .agents/templates/plan.md \
         .agents/templates/task.md \
         .agents/templates/manifest.md \
         .agents/templates/review.md \
         CONTEXT.md ARCHITECTURE.md RULES.md; do
  [ -f "$f" ] && ok "init writes $f" || bad "init did not write $f"
done

# The templates are instructions; the files they produce are work. Shipping
# a filled-in .agents/plan.md would be shipping half a change, and the
# pointer check below asserts the same thing from the other side.
for f in .agents/plan.md .agents/manifest.md; do
  [ -e "$f" ] && bad "init pre-made $f — that is the agent's to write" \
               || ok "init does not pre-make $f"
done

# Vendored work travels with its own licence, in its own directory. One
# LICENSE at the top for five skills from three authors leaves a reader
# guessing which terms cover what.
for s in grill-me ponytail humanizer; do
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
products='.agents/plan.md .agents/manifest.md .agents/tasks .agents/reviews'

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
for stage in grill plan task subtask build manifest commit brief findings close; do
  grep -qi "$stage" "$R/.agents/leo.md" \
    && ok "leo.md defines the $stage stage" \
    || bad "AGENTS.md names $stage and leo.md never explains it"
done

# The mode table and the skills that exist have to be the same set.
for skill in grill-me tdd ponytail caveman humanizer; do
  grep -qi "$skill" "$R/AGENTS.md" \
    && ok "AGENTS.md maps $skill to modes" \
    || bad "$skill ships but AGENTS.md never says when to use it"
done
for tool in graph rtk; do
  grep -qi "$tool" "$R/AGENTS.md" \
    && ok "AGENTS.md names the $tool tool" \
    || bad "$tool ships but AGENTS.md never mentions it"
done

# Every template the documents tell the agent to copy must be a file the
# copier ships. This is the same dangling-pointer failure as a missing skill,
# one indirection further along.
for t in plan task manifest review; do
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
for pair in "ponytail 6637" "humanizer 28728"; do
  set -- $pair
  n=$(wc -c < "$R/.agents/skills/$1/SKILL.md" | tr -d ' ')
  [ "$n" = "$2" ] && ok "$1/SKILL.md is $2 bytes, as upstream" \
                  || bad "$1/SKILL.md is $n bytes, upstream is $2 — it has been edited"
done
grep -q 'Matt Pocock' "$R/.agents/skills/grill-me/LICENSE" \
  && ok "grill-me carries Matt Pocock's licence" \
  || bad "grill-me's licence is missing or wrong"
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
