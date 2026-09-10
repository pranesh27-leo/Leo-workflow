#!/usr/bin/env bash
# desc: run the rules, the manifest, the grill, the tools, TDD, the budget and the tests
# usage: leo check [--verbose]
#
# Seven checks, in the order that catches mistakes cheapest-first. Read this file
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
else
  # No manifest and recorded cycles waiting means the manifest was consumed by
  # `leo record`. HEAD would then measure every recorded cycle against the
  # current plan's estimate and fail the budget on work that was already
  # checked and accounted for.
  _base=$(record_base)
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

  # And the manifest must still describe the tree it is being checked against.
  #
  # `leo scan` takes a snapshot; everything above validates that snapshot's
  # rows. None of it asks whether the snapshot is still true, and work does not
  # stop when the scan runs -- so a file written afterwards had no row, no task
  # and no complaint. "all checks passed", straight into the commit. That is
  # the one guarantee leo makes, defeated by a stale file rather than by
  # anything anyone argued for.
  #
  # Only files that appeared. A file the manifest covers and the tree no longer
  # has is a revert, which is a normal thing to do mid-change and not something
  # to fail a check over.
  # One pass, not one grep per changed file: this runs on every check, and a
  # repository with a few hundred touched files made the loop version cost
  # more than every other stage put together.
  _cov=$(mktemp "${TMPDIR:-/tmp}/leo-cov.XXXXXX")
  awk -F'|' '
    /^\| *[0-9NEW]/ {
      h = $3
      gsub(/[ \t`]/, "", h)          # `path:line` -> path:line
      sub(/:[0-9]*$/, "", h)         # drop the line number
      if (h != "") print h
    }' "$MANIFEST" | sort -u > "$_cov"
  # An empty pattern file matches nothing, so -v then yields every changed
  # file -- which is right: a manifest with no rows covers nothing.
  _new=$(changed "$_base" | grep -vxF -f "$_cov" || true)
  rm -f "$_cov"
  if [ -n "$_new" ]; then
    err "file(s) appeared since the scan and are in no manifest row:"
    printf '%s\n' "$_new" | sed 's/^/       /' >&2
    dim "  the manifest describes a diff that has moved on — rescan it:"
    dim "  rm .leo/manifest.md && leo scan"
    _fail=1
  else
    ok "the manifest still covers the tree"
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
    dim "  no limit on questions or rounds — stop on shared understanding"
    _fail=1
  else
    ok "$_task has been grilled"
  fi
fi

# --- 4. tools -------------------------------------------------------------
# The switch, enforced. A tool that is ON must have left its mark; a tool that
# is OFF must not have. Which mark depends on the kind -- see the tools section
# in core/lib.sh for why there are two.
#
# Only with a session declared. No mode means nothing was switched on or off,
# and failing a change for not using tools nobody asked for would be leo
# inventing a policy the developer never set.
#
# And only with a cycle in flight. The manifest is what says there are hunks
# here that something built; the ledger answers "what built them", and the two
# are consumed together by `leo record`. Without this guard `leo commit`
# deadlocked: it re-runs the checks, the record had already cleared both, and
# the tools stage failed every landing for evidence that no longer described
# anything. Each record was checked when it was made.
if [ -n "$MODE" ] && [ -f "$MANIFEST" ]; then
  head_ "tools"
  _tn=0
  for _c in $CAPS; do
    _kind=$(cap_kind "$_c")
    # A practice is not a tool the agent invokes, and it gets its own stage
    # below. Filing it here would ask the agent to announce using TDD, which
    # means nothing.
    [ "$_kind" = "practice" ] && continue
    _tn=$((_tn + 1))
    _st=$(cap_state "$_c")
    _lb=$(cap_call "$_c" label); _lb="${_lb:-$_c}"

    if [ "$_st" = "on" ]; then
      _pr=0; cap_present "$_c" || _pr=$?
      if [ "$_pr" -eq 1 ]; then
        # A tool that is not installed could not have been used, so this is
        # never the agent's failure -- and it is not news either. Whether
        # something is installed does not change between two checks, and
        # `leo session` already prints "Not installed" where it is actionable.
        # As a warn it survived the terse filter and put four lines into the
        # context of every passing check, forever, which is the exact cost
        # .leo/rules/ALWAYS-LOADED.md exists to stop. dim is buffered away on
        # success and replayed in full on failure.
        dim "  $_lb is ON and not installed — leo install $_c"
      elif [ "$_pr" -eq 2 ]; then
        dim "  $_lb is ON and leo has no adapter for it — nothing to verify"
      elif [ "$_kind" = "invoked" ]; then
        if used_has "$_c"; then
          ok "$_lb used"
        else
          err "$_lb is ON and was never used — announce it: leo use $_c"
          dim "  or it is not wanted here, which is the developer's call:"
          dim "  leo session --$_c off"
          _fail=1
        fi
      else
        ok "$_lb in effect"
      fi
    elif used_has "$_c"; then
      # The one violation that is unambiguous: the developer switched it off
      # and the ledger says it was used anyway.
      if [ "$(used_note "$_c")" = "DENIED" ]; then
        err "$_lb is OFF and was used anyway, after leo refused it"
      else
        err "$_lb is OFF and was used anyway"
      fi
      dim "  the mode is the developer's — .leo/used records the attempt"
      _fail=1
    fi
  done
  [ "$_tn" -eq 0 ] && dim "  no tools declared"
fi

# --- 5. TDD ---------------------------------------------------------------
# The practice, enforced the same way as the grill: a mark leo can grep. With
# TDD on, `leo task` seeds the red-before-green steps into the to-do; this
# fails while the "watch it FAIL" step is still unticked and there are already
# hunks in the manifest. Code exists, and nothing ever watched a test fail for
# the reason it was supposed to.
#
# Only when leo seeded the step. A task file written before TDD was turned on
# has no such line, and inventing a failure for its absence would punish the
# developer for changing their mind.
if [ "$(cap_state tdd)" = "on" ] && [ -f "$MANIFEST" ]; then
  head_ "tdd"
  _tt=$(task_current)
  _tf=""
  [ -n "$_tt" ] && _tf=$(task_file "$_tt")
  if [ -z "$_tt" ] || [ ! -f "$_tf" ]; then
    dim "  no task in flight"
  elif grep -q '^- \[ \].*watch it FAIL' "$_tf" 2>/dev/null; then
    err "$_tt has hunks in the manifest but never watched a test fail"
    dim "  - [ ] run it, watch it FAIL, and confirm it failed for the reason you expect"
    dim "  tick it once you have, or turn the practice off: leo session --tdd off"
    _fail=1
  else
    ok "$_tt watched its test fail first"
  fi
fi

# --- 6. budget ------------------------------------------------------------
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

# --- 7. tests -------------------------------------------------------------
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
