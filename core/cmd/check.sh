#!/usr/bin/env bash
# desc: run the rules, the manifest check, the budget check and the tests
# usage: leo check [--verbose]
#
# Four checks, in the order that catches mistakes cheapest-first. Read this file
# top to bottom -- there is no plugin system and no hidden ordering.
#
# Quiet on success, loud on failure. This used to print 26 lines every time it
# passed, and in an agent session every one of those lines is re-read on every
# turn for the rest of the session -- a passing check is the least informative
# thing leo prints and it was the most expensive. Warnings still come through:
# terse means "hide what went right", not "hide what you need to know".

need_repo

_verbose=0
while [ $# -gt 0 ]; do
  case "$1" in
    --verbose|-v) _verbose=1; shift ;;
    -*)           die "unknown option: $1" ;;
    *)            die "unexpected argument: $1" ;;
  esac
done

# Everything the stages print goes to a buffer first. On failure the buffer is
# replayed whole -- a failure is rare and the detail is the entire point. On
# success only the warnings and one summary line survive.
_buf=$(mktemp "${TMPDIR:-/tmp}/leo-check.XXXXXX")
trap 'rm -f "$_buf"' EXIT
if [ "$_verbose" -eq 0 ]; then
  exec 3>&2 2>"$_buf"
fi

# The base is whatever `leo scan` reviewed against, so the budget can never be
# measured against a different starting point than the manifest was. Guard the
# read: under `set -e` a substitution over a missing file takes the whole
# command down, silently.
_base=HEAD
if [ -f "$MANIFEST" ]; then
  _base=$(sed -n 's/^Base: *//p' "$MANIFEST" | head -1)
  _base="${_base:-HEAD}"
fi
_fail=0

# --- 1. rules -------------------------------------------------------------
# A rule is a markdown file with a shell command under "## Verify" that exits
# non-zero when the mistake is present. Zero tokens, ~1s, and it keeps working
# after the agent that learned the lesson is gone.
head_ "rules"
_n=0
for _rule in "$RULES"/*.md; do
  [ -f "$_rule" ] || continue
  _id=$(basename "$_rule" .md)
  case "$_id" in EXAMPLE|TEMPLATE) continue ;; esac

  _cmd=$(awk '
    /^## Verify/ { v = 1; next }
    v && /^```/  { c++; if (c == 1) next; if (c == 2) exit }
    v && c == 1  { print }' "$_rule")

  [ -n "$_cmd" ] || { warn "$_id has no Verify block — skipped"; continue; }
  _n=$((_n + 1))

  if _out=$(cd "$ROOT" && bash -c "$_cmd" 2>&1); then
    ok "$_id"
  else
    err "$_id violated"
    printf '%s\n' "$_out" | sed 's/^/       /' >&2
    _fail=1
  fi
done
[ "$_n" -eq 0 ] && dim "  no rules yet — write one the next time you fix a real bug"

# --- 2. manifest ----------------------------------------------------------
# Every hunk must name the task it serves, and that task must be one the plan
# actually declared. Those two together are what turns "500 lines arrived" into
# "these 40 lines are here because someone felt like it".
head_ "manifest"
if [ ! -f "$MANIFEST" ]; then
  warn "no manifest — run: leo scan"
else
  # Blank means nobody looked at it yet: that is a failure. An explicit "-"
  # means someone looked and owned the answer: that is scope creep, reported in
  # lines so the cost is visible.
  _blank=$(awk -F'|' '/^\| *[0-9NEW]/ { t = $5; gsub(/[ \t]/, "", t); if (t == "") n++ } END { print n + 0 }' "$MANIFEST")
  _creep=$(awk -F'|' '/^\| *[0-9NEW]/ { t = $5; gsub(/[ \t]/, "", t); if (t == "-") n++ } END { print n + 0 }' "$MANIFEST")
  _creep_loc=$(awk -F'|' '
    /^\| *[0-9NEW]/ {
      t = $5; gsub(/[ \t]/, "", t)
      if (t == "-" && match($4, /\+[0-9]+/)) loc += substr($4, RSTART + 1, RLENGTH - 1)
    }
    END { print loc + 0 }' "$MANIFEST")

  if [ "$_blank" -gt 0 ]; then
    err "$_blank hunk(s) not reviewed — every row needs Task, Why and If deleted"
    _fail=1
  else
    ok "every hunk reviewed"
  fi

  # A task ID that is not in the plan is an invented justification. This is the
  # one dishonest move that would otherwise sail through the whole workflow.
  # `|| true` for the same reason as plan_est: no plan, or a plan with no task
  # rows, is a state to report -- not one to die in.
  _known=$(grep -o '^| *T[0-9][0-9]*' "$PLAN" 2>/dev/null | tr -d ' |' | sort -u || true)
  _used=$(awk -F'|' '/^\| *[0-9NEW]/ { t = $5; gsub(/[ \t]/, "", t); if (t != "" && t != "-") print t }' "$MANIFEST" | sort -u)
  if [ -z "$_known" ]; then
    warn "the plan declares no tasks — nothing to check hunks against"
  elif [ -n "$_used" ]; then
    _invented=0
    for _t in $_used; do
      printf '%s\n' "$_known" | grep -qx "$_t" || {
        err "$_t is not a task in the plan — never invent a task ID to justify a hunk"
        _invented=1; _fail=1
      }
    done
    [ "$_invented" -eq 0 ] && ok "every task ID is one the plan declared"
  fi

  if [ "$_creep" -gt 0 ]; then
    warn "$_creep hunk(s), $_creep_loc lines, serve no task — revert, promote or split"
  fi
fi

# --- 3. grill -------------------------------------------------------------
# Every task is grilled, and so is every subtask. This is the one place in leo
# where a task file blocks anything, and it is deliberate: a task nobody
# questioned is a task built on whatever the agent assumed, and the assumption
# becomes code before anyone sees it.
#
# Only the task being worked on. Grilling T5 while you are on T1 would mean
# answering questions about code that does not exist yet, and the answers would
# be guesses -- which is the thing this is trying to prevent.
head_ "grill"
_task=$(task_current)
if [ -z "$_task" ]; then
  dim "  no task in flight"
elif [ ! -f "$(task_file "$_task")" ]; then
  # Not a failure: the task stage simply has not happened yet, and `leo task`
  # is what happens next. Saying so beats failing a check for a file whose
  # absence is the normal state five minutes into a change.
  warn "$_task has no file yet — run: leo task $_task"
else
  _tf=$(task_file "$_task")
  _un=$(grep -c 'leo:ungrilled' "$_tf" 2>/dev/null || true)
  _un=${_un:-0}
  if [ "$_un" -gt 0 ]; then
    err "$_task is ungrilled ($_un section(s)) — grill it, record what it settled"
    dim "  the grill itself: .leo/skills/grilling/SKILL.md"
    dim "  scale it to the work; one question is fine, zero is not"
    _fail=1
  else
    ok "$_task has been grilled"
  fi
fi

# --- 4. budget ------------------------------------------------------------
# An overshoot past 2x almost always means the requirement was misread, not
# that the work was genuinely bigger. Re-plan; do not review harder.
head_ "budget"
_est=$(plan_est)
if [ -z "$_est" ] || [ "$_est" -eq 0 ] 2>/dev/null; then
  warn "no estimate in the plan — declare one: 'est: <n> LOC'"
else
  _actual=$(lines_changed "$_base")
  if [ "$_actual" -gt $((_est * 2)) ]; then
    err "est $_est LOC, actual $_actual LOC (over 2x) — re-read the request before reviewing"
    _fail=1
  else
    ok "est $_est LOC / actual $_actual LOC"
  fi
fi

# --- 5. tests -------------------------------------------------------------
head_ "tests"
_result=""
if [ -z "$TEST_CMD" ]; then
  warn "TEST_CMD unset in .leo/config — leo cannot verify anything for you"
else
  # LEO_YES is leo's own control variable, and it must not reach the tests.
  # `LEO_YES=1 leo commit` exports it to everything downstream, including
  # TEST_CMD -- and a suite that exercises leo's own refusal to commit without
  # a human then watches that refusal not happen. leo's smoke test found this
  # by failing; any project testing similar behaviour would hit it too.
  if _out=$(cd "$ROOT" && unset LEO_YES && eval "$TEST_CMD" 2>&1); then
    ok "$TEST_CMD"
    printf '%s\n' "$_out" | tail -3 | sed 's/^/       /' >&2
    _result="\`$TEST_CMD\` -- passed, $(now)"
  else
    err "$TEST_CMD failed"
    printf '%s\n' "$_out" | tail -15 | sed 's/^/       /' >&2
    _result="\`$TEST_CMD\` -- FAILED, $(now)"
    _fail=1
  fi
fi

# The Tests: line is evidence, and evidence nobody typed cannot be wishful. leo
# writes it from the run it just did; a leftover placeholder means no run.
if [ -f "$MANIFEST" ]; then
  if [ -n "$_result" ]; then
    _tmp=$(mktemp "${TMPDIR:-/tmp}/leo-m.XXXXXX")
    awk -v r="Tests: $_result" '/^Tests:/ { print r; next } { print }' "$MANIFEST" > "$_tmp"
    mv "$_tmp" "$MANIFEST"
  elif grep -q '^Tests:.*<' "$MANIFEST"; then
    err "the manifest still claims nothing about tests — run them and record the real output"
    _fail=1
  fi
fi

echo >&2

# Restore the real stderr before anything else is printed, or the summary ends
# up in the buffer it is summarising.
if [ "$_verbose" -eq 0 ]; then
  exec 2>&3 3>&-
fi

if [ "$_fail" -ne 0 ]; then
  [ "$_verbose" -eq 0 ] && cat "$_buf" >&2
  # The mode is worth one line here and nowhere else: a check that fails while
  # the session is still set to coding is the moment someone realises they have
  # been debugging for an hour with the reducers on.
  [ -n "$MODE" ] && dim "  session mode: $MODE"
  die "check failed"
fi

if [ "$_verbose" -eq 0 ]; then
  # Warnings are not "what went right". A hunk serving no task, a missing
  # manifest, a capability declared and not installed -- each is something the
  # developer has to decide about, and swallowing it to save four lines would
  # be buying tokens with the thing the tokens were for.
  grep -a '^warn' "$_buf" >&2 || true

  # Every one of these three greps legitimately matches nothing -- no rules
  # directory, no manifest, a plan with no estimate -- and under `pipefail` a
  # grep that matches nothing fails the whole assignment, which `set -e` then
  # turns into the command exiting 1 with the summary never printed. That is
  # exactly the failure `plan_est` in lib.sh carries a comment about, and it
  # presented here as "check dies silently on a repo with no plan".
  _nrules=$(ls "$RULES"/*.md 2>/dev/null | wc -l | tr -d ' ' || printf 0)
  _nhunks=$(grep -ac '^| *[0-9NEW]' "$MANIFEST" 2>/dev/null || printf 0)
  _bud=$(grep -ao 'est [0-9]* LOC / actual [0-9]* LOC' "$_buf" 2>/dev/null | head -1 || true)
  ok "all checks passed"
  printf '  %s rule(s)%s%s\n' \
    "${_nrules:-0}" \
    "$([ "${_nhunks:-0}" -gt 0 ] && printf ', %s hunk(s) reviewed' "$_nhunks")" \
    "${_bud:+, $_bud}" >&2
  dim "  leo check --verbose to see every stage"
else
  ok "all checks passed"
fi
