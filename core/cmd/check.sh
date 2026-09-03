#!/usr/bin/env bash
# desc: run the rules, the manifest check, the budget check and the tests
# usage: leo check [base]
#
# Four checks, in the order that catches mistakes cheapest-first. Read this file
# top to bottom -- there is no plugin system and no hidden ordering.

need_repo

_base="${1:-HEAD}"
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
  _known=$(grep -o '^| *T[0-9][0-9]*' "$PLAN" 2>/dev/null | tr -d ' |' | sort -u)
  if [ -n "$_known" ]; then
    _invented=0
    for _t in $(awk -F'|' '/^\| *[0-9NEW]/ { t = $5; gsub(/[ \t]/, "", t); if (t != "" && t != "-") print t }' "$MANIFEST" | sort -u); do
      printf '%s\n' "$_known" | grep -qx "$_t" || {
        err "$_t is not a task in the plan — never invent a task ID to justify a hunk"
        _invented=1; _fail=1
      }
    done
    [ "$_invented" -eq 0 ] && ok "every task ID is one the plan declared"
  else
    warn "the plan declares no tasks — nothing to check hunks against"
  fi

  if [ "$_creep" -gt 0 ]; then
    warn "$_creep hunk(s), $_creep_loc lines, serve no task — revert, promote or split"
  fi
fi

# --- 3. budget ------------------------------------------------------------
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

# --- 4. tests -------------------------------------------------------------
head_ "tests"
_result=""
if [ -z "$TEST_CMD" ]; then
  warn "TEST_CMD unset in .leo/config — leo cannot verify anything for you"
else
  if _out=$(cd "$ROOT" && eval "$TEST_CMD" 2>&1); then
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
[ "$_fail" -eq 0 ] || die "check failed"
ok "all checks passed"
