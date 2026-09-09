#!/usr/bin/env bash
# desc: open, show or close a review of a change that has already landed
# usage: leo review [<rev>]       open a review of <rev> (default HEAD), or show it
#        leo review <a>..<b>      review a range as one review, keyed by its tip
#        leo review --list        every review in this repository
#        leo review --close       check the open review and hand it back
#
# This is cycle two, and it starts where cycle one stops. The dev cycle ends at
# `leo commit`; nothing in this file can change that commit, and that is the
# point -- a reviewer who can edit the change under review is not reviewing it,
# they are finishing it.
#
# The dev cycle is not re-derived here, it is *read*. `leo commit` writes the
# goal, the whole manifest and the session trailer into the commit message, so
# `git show` alone says what was asked for, why each hunk exists and what was
# mediating the agent's view of the code when it wrote them. That is what the
# "What was asked for" section is assembled from. A review that does not know
# what was asked can only check the code against itself, which is how a change
# that is internally consistent and completely wrong passes.
#
# What the shell does here is what the shell can do honestly: quote the dev
# cycle, and point at the lines worth a second look. Every judgement in the
# file is written by whoever runs the review.

need_repo

_rev=""; _close=0; _list=0; _force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --close) _close=1; shift ;;
    --list)  _list=1; shift ;;
    --force) _force=1; shift ;;
    -*)      die "unknown option: $1" ;;
    *)       [ -z "$_rev" ] || die "unexpected argument: $1"; _rev="$1"; shift ;;
  esac
done

mkdir -p "$REVIEWS"

# --- list -----------------------------------------------------------------
if [ "$_list" -eq 1 ]; then
  head_ "leo review"
  _n=0
  for _f in "$REVIEWS"/*.md; do
    [ -f "$_f" ] || continue
    _n=$((_n + 1))
    printf '  %-10s %-9s %-5s %s\n' \
      "$(basename "$_f" .md)" \
      "$(review_state "$_f")" \
      "$(review_count "$_f" blocker)b/$(review_count "$_f" '' )f" \
      "$(review_subject "$_f")" >&2
  done
  [ "$_n" -eq 0 ] && dim "  no reviews yet — leo review <rev>"
  exit 0
fi

# --- close ----------------------------------------------------------------
# The gate of cycle two, and the only thing in it that refuses. It checks the
# vocabulary (so the columns stay machine-readable), that every finding has
# been dispositioned, and that the verdict is a real sentence rather than the
# placeholder the template shipped with. It never decides whether the code is
# good -- that is written in the file by whoever read it.
if [ "$_close" -eq 1 ]; then
  _f=$(review_pick "$_rev") || exit 1
  _id=$(basename "$_f" .md)
  _fail=0

  head_ "closing review $_id"

  # 1. vocabulary. A status leo cannot read is a finding nobody dispositioned,
  # and it must not pass by being unparseable.
  _bad=$(awk -F'|' '
    /^\| *[0-9]/ {
      s = $3; gsub(/[ \t`]/, "", s)
      t = $7; gsub(/[ \t`]/, "", t)
      n = $2; gsub(/[ \t]/, "", n)
      if (s != "blocker" && s != "improvement" && s != "nit") print "  row " n ": severity \"" s "\" is not blocker/improvement/nit"
      else if (t != "open" && t != "fixed" && t != "waived") print "  row " n ": status \"" t "\" is not open/fixed/waived"
    }' "$_f")
  if [ -n "$_bad" ]; then
    err "the findings table does not read"
    printf '%s\n' "$_bad" >&2
    _fail=1
  fi

  # 2. open blockers. The one thing that holds a review open.
  _open=$(review_count "$_f" blocker open)
  if [ "$_open" -gt 0 ]; then
    err "$_open blocker(s) still open — fix them in a new dev cycle, or waive them"
    awk -F'|' '
      /^\| *[0-9]/ {
        s = $3; gsub(/[ \t`]/, "", s); t = $7; gsub(/[ \t`]/, "", t)
        if (s == "blocker" && t == "open") {
          w = $4; gsub(/^[ \t]+|[ \t]+$/, "", w)
          d = $5; gsub(/^[ \t]+|[ \t]+$/, "", d)
          printf "  %s  %s\n", w, d
        }
      }' "$_f" >&2
    dim "  a fix is a dev cycle, not an edit: leo plan \"fix: $_id review\""
    dim "  waiving one is the developer's call, and it stays in the file"
    _fail=1
  fi

  # 3. the verdict. Same test as the manifest's Tests: line -- a conclusion
  # nobody typed is not a conclusion, and the template's placeholder is how
  # you tell.
  _v=$(review_verdict "$_f")
  case "$_v" in
    ""|*"<"*) err "the review states no verdict — say ship or fix-first, and why"; _fail=1 ;;
  esac

  [ "$_fail" -ne 0 ] && die "review $_id stays open"

  # The stamp, written from something that actually happened -- the same
  # principle as the manifest's `Tests:` line. Until it is here the review is
  # merely ready; a review nobody signed is not a review that closed.
  if grep -q '^Closed:' "$_f"; then
    _tmp=$(mktemp "${TMPDIR:-/tmp}/leo-rv.XXXXXX")
    awk -v s="Closed: $(now)" '/^Closed:/ { print s; next } { print }' "$_f" > "$_tmp"
    mv "$_tmp" "$_f"
  else
    printf 'Closed: %s\n' "$(now)" >> "$_f"
  fi

  _nb=$(review_count "$_f" blocker)
  _nf=$(review_count "$_f")
  _waived=$(review_count "$_f" blocker waived)
  ok "review $_id closes — $_nf finding(s), $_nb blocker(s), $_waived waived"
  [ "$_waived" -gt 0 ] && warn "$_waived waived blocker(s) — they stay in the file, and in the log"

  # Everything still open that is not a blocker is a backlog, not a failure.
  _rest=$(review_count "$_f" improvement open)
  _rest=$((_rest + $(review_count "$_f" nit open)))
  [ "$_rest" -gt 0 ] && dim "  $_rest open improvement(s)/nit(s) — a dev cycle when you want them, not now"

  info ""
  info "The review is a record of a commit that already exists, so unlike the"
  info "plan and the manifest it has nowhere to live but the repository:"
  dim  "  git add ${_f#"$ROOT"/} && git commit -m \"review: $_id — ${_v%% *}, $_nf finding(s)\""
  exit 0
fi

# --- open, or show --------------------------------------------------------
_rev="${_rev:-HEAD}"
case "$_rev" in
  *..*) _range=1; _tip="${_rev##*..}"; _tip="${_tip:-HEAD}" ;;
  *)    _range=0; _tip="$_rev" ;;
esac
git rev-parse --verify --quiet "$_tip^{commit}" >/dev/null 2>&1 \
  || die "'$_rev' is not a commit this repository has"
_sha=$(git rev-parse --short "$_tip")
_f="$REVIEWS/$_sha.md"

if [ -f "$_f" ] && [ "$_force" -eq 0 ]; then
  cat "$_f"
  info ""
  dim "  $(review_state "$_f") — leo review --close when the findings are dispositioned"
  dim "  leo review $_rev --force replaces it, and loses what is written above"
  exit 0
fi

# The diff under review. A range is diffed end to end; a single commit is shown
# as itself, so a review of an old commit reads that commit and not everything
# since. -U0 for both: hunks, not context, exactly as `leo scan` takes them.
_diff() {
  if [ "$_range" -eq 1 ]; then git diff -U0 "$_rev"; else git show -U0 --format= "$_rev"; fi
}

_msg=$(git show -s --format=%B "$_tip")
_subject=$(printf '%s\n' "$_msg" | head -1)

# --------------------------------------------------------------- context ---
# What the dev cycle recorded, quoted rather than summarised. Every part of
# this is already written down somewhere; the value is having it in one place
# before the diff is read, not in having it restated.
_ctx=$(
  printf 'Commit:  %s  (%s, %s)\n' "$_sha" \
    "$(git show -s --format=%an "$_tip")" "$(git show -s --format=%ad --date=short "$_tip")"
  [ "$_range" -eq 1 ] && printf 'Range:   %s\n' "$_rev"
  printf 'Subject: %s\n' "$_subject"

  # The goal and the trailers leo itself wrote into the message.
  _goal=$(printf '%s\n' "$_msg" | sed -n 's/^Goal: *//p' | head -1)
  [ -n "$_goal" ] && printf 'Goal:    %s\n' "$_goal"
  _sess=$(printf '%s\n' "$_msg" | sed -n 's/^Session: *//p' | head -1)
  [ -n "$_sess" ] && printf 'Session: %s\n' "$_sess"
  _by=$(printf '%s\n' "$_msg" | sed -n 's/^Assisted-by: *//p' | head -1)
  [ -n "$_by" ] && printf 'Written: %s\n' "$_by"

  # The manifest, straight out of the commit message. This is the dev cycle's
  # own answer to "why does this hunk exist", and the review's job is to test
  # it against the code -- not to write it again.
  _man=$(printf '%s\n' "$_msg" | grep '^| ' || true)
  if [ -n "$_man" ]; then
    printf '\n### The manifest this commit was made with\n\n'
    printf '%s\n' "$_man"
    _b=$(printf '%s\n' "$_msg" | grep '^Budget:' || true)
    _t=$(printf '%s\n' "$_msg" | grep '^Tests:'  || true)
    [ -n "$_b" ] && printf '\n%s\n' "$_b"
    [ -n "$_t" ] && printf '%s\n' "$_t"
  else
    printf '\n### No manifest in this commit message\n\n'
    printf 'The change was committed without one, so nothing here says why any\n'
    printf 'hunk exists. Read the diff with that in mind, and say so in the\n'
    printf 'verdict -- it is a finding about the change, not about the review.\n'
  fi

  # The plan is working state and survives on disk after the commit. It may
  # well be the next change's plan by the time anyone reads this, so it is
  # labelled rather than presented as fact.
  if [ -f "$PLAN" ]; then
    _ng=$(awk '
      /^## Non-goals/    { g = 1; next }
      g && (/^## / || /^\| / || /^est:/) { exit }
      g && NF && $0 !~ /^</ { print "  " $0 }' "$PLAN")
    _ws=$(awk '
      /^## Wrong-change/ { g = 1; next }
      g && (/^## / || /^\| / || /^est:/) { exit }
      g && NF && $0 !~ /^</ { print "  " $0 }' "$PLAN")
    if [ -n "$_ng$_ws" ]; then
      printf '\n### From .leo/plan.md — "%s"\n' "$(plan_name)"
      printf '\n(Still on disk. Check it is this change before you trust it.)\n'
      [ -n "$_ng" ] && { printf '\nNon-goals — a hunk that serves one of these is a finding:\n\n'; printf '%s\n' "$_ng"; }
      [ -n "$_ws" ] && { printf '\nWrong-change signal:\n\n'; printf '%s\n' "$_ws"; }
    fi
  fi

  # The grill: the decisions behind the code, which the diff cannot show. This
  # is the part of the dev cycle a reviewer most often has to guess at, and the
  # one place leo already has it written down.
  _g=""
  for _tf in "$TASKS"/*.md; do
    [ -f "$_tf" ] || continue
    _tid=$(basename "$_tf" .md)
    _body=$(awk '
      /^## Grill/     { g = 1; next }
      g && /^## /     { g = 0 }
      g && /^<!--/    { c = 1 }
      c && /-->/      { c = 0; next }
      c               { next }
      g && NF && $0 !~ /^</ { print "  " $0 }' "$_tf")
    [ -n "$_body" ] && _g="$_g$_tid:
$_body
"
  done
  if [ -n "$_g" ]; then
    printf '\n### What the grill settled — from .leo/tasks/\n'
    printf '\nDecisions the code cannot record. A finding that contradicts one of\n'
    printf 'these is really a finding about the decision, so say that.\n\n'
    printf '%s' "$_g"
  fi
)

# --------------------------------------------------------------- signals ---
# Deterministic, and deliberately dumb. Each of these is a grep whose only
# claim is "a human should glance here" -- most will be nothing, and clearing
# one costs a glance. Nothing below decides anything, so nothing below can be
# wrong in a way that matters; a signal leo does not raise is the failure mode,
# not a signal it raises for a line that turns out to be fine.
_added=$(mktemp "${TMPDIR:-/tmp}/leo-review.XXXXXX")
trap 'rm -f "$_added"' EXIT

# Every added line as file<TAB>line<TAB>text. The line numbers are the ones in
# the new file, tracked off the hunk headers, so a signal points at something
# you can actually open.
_diff | awk '
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^--- /       { next }
  /^@@/ {
    s = $0; sub(/^@@ [^+]*\+/, "", s); split(s, a, " "); split(a[1], b, ",")
    ln = b[1] + 0; next
  }
  /^\+/ && file != "" { printf "%s\t%d\t%s\n", file, ln, substr($0, 2); ln++ }
' > "$_added"

# _flag <title> <lowercase-ere> — the added lines whose *text* matches. The
# path is excluded from the match on purpose: half these patterns are ordinary
# words in a filename, and `auth/token.go` would otherwise light up every
# signal it has a word for.
_flag() {
  _hits=$(LEO_PAT="$2" awk -F"\t" '
    BEGIN { p = ENVIRON["LEO_PAT"] }
    { t = $0; sub(/^[^\t]*\t[^\t]*\t/, "", t); sub(/^[ \t]+/, "", t) }
    tolower(t) ~ p {
      n++
      if (n <= 10) printf "  %s:%s  %s\n", $1, $2, substr(t, 1, 100)
    }
    END { if (n > 10) printf "  ... and %d more\n", n - 10 }' "$_added")
  [ -n "$_hits" ] || return 0
  printf '### %s\n\n```\n%s\n```\n\n' "$1" "$_hits"
}

_files=$(_diff | awk '/^\+\+\+ b\// { print substr($0, 7) }' | sort -u)
_testpat='(^|/)(tests?|spec|__tests__)/|(^|[._-])(test|spec)[._-]|_test\.|\.test\.|\.spec\.|(^|/)test_'

_sig=$(
  # Security first, and split rather than lumped: "security" as one heading is
  # long enough that it gets skimmed, and the three kinds want different eyes.
  _flag 'Secrets — a literal assigned to a credential-shaped name' \
    '(password|passwd|secret|token|api_?key|access_?key|private_?key|credential)[a-z_]*["'"'"' ]*[:=][ ]*["'"'"'][^"'"'"']{8,}'
  _flag 'Untrusted input reaching an interpreter' \
    '(exec\(|eval\(|system\(|popen|subprocess|child_process|shell *= *true|innerhtml|dangerouslysetinnerhtml|document\.write|pickle\.load|yaml\.load|deserial|select .* from|insert into|delete from|\.raw\(|execute\()'
  _flag 'Authentication, authorisation and crypto' \
    '(authenticat|authoriz|permission|is_?admin|\brole\b|session|jwt|oauth|bcrypt|hmac|cipher|encrypt|decrypt|md5|sha1|math/rand|random\.)'
  _flag 'Errors that may be going nowhere' \
    '(except:|except exception|rescue *(=>|$)|catch[^{]*\{ *\}|_ = err|\.unwrap\(\)|@ts-ignore|eslint-disable|# *nolint|// *nolint|type: *ignore)'
  _flag 'Left in by accident' \
    '(todo|fixme|xxx|hack:|console\.log|debugger|binding\.pry|pdb\.set_trace|breakpoint\(\)|dbg!|fmt\.print)'

  # Dependencies: a changed manifest is a supply-chain decision, and it is one
  # of the few things a reviewer can check faster than the author can.
  _deps=$(printf '%s\n' "$_files" | grep -Ei '(^|/)(package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|go\.mod|go\.sum|requirements[^/]*\.txt|pyproject\.toml|poetry\.lock|Pipfile|Cargo\.toml|Cargo\.lock|Gemfile|Gemfile\.lock|pom\.xml|build\.gradle[^/]*|composer\.json|composer\.lock|mix\.exs|pubspec\.yaml|[^/]*\.csproj)$' || true)
  [ -n "$_deps" ] && printf '### Dependency manifests changed\n\n```\n%s\n```\n\n' "$(printf '%s\n' "$_deps" | sed 's/^/  /')"

  # Tests, as a count rather than a judgement. "No test file changed" is not
  # automatically wrong -- a refactor covered by existing tests is the normal
  # case -- but it is always worth one sentence in the review.
  _ns=$(printf '%s\n' "$_files" | grep -Ev "$_testpat" | grep -c . || true)
  _nt=$(printf '%s\n' "$_files" | grep -Ec "$_testpat" || true)
  printf '### Tests\n\n%s source file(s) changed, %s test file(s) changed.\n' "${_ns:-0}" "${_nt:-0}"
  if [ "${_nt:-0}" -eq 0 ] && [ "${_ns:-0}" -gt 0 ]; then
    printf '\nNo test file changed. Ask the standards question: is there a test\n'
    printf 'that fails without this change? If not, say so as a finding.\n'
  fi
  printf '\n'

  # Big hunks. Not a defect, but review attention is finite and this is where
  # it goes first -- a 200-line hunk gets skimmed unless something says not to.
  _big=$(_diff | awk '
    function flush() { if (open && add > 60) printf "  %s:%s  +%d/-%d\n", file, start, add, del
                       open = 0; add = 0; del = 0 }
    /^diff --git / { flush(); next }
    /^\+\+\+ b\//  { file = substr($0, 7); next }
    /^--- /        { next }
    /^@@/ { flush()
            s = $0; sub(/^@@ [^+]*\+/, "", s); split(s, a, " "); split(a[1], b, ",")
            start = b[1]; open = 1; next }
    open && /^\+/ { add++ }
    open && /^-/  { del++ }
    END { flush() }')
  [ -n "$_big" ] && printf '### Hunks over 60 added lines\n\n```\n%s\n```\n\n' "$_big"

  # The dev cycle's own admission, carried forward. A hunk that served no task
  # went in anyway; whether that was fine is a review question.
  _creep=$(printf '%s\n' "$_msg" | awk -F'|' '
    /^\| *[0-9NEW]/ { t = $5; gsub(/[ \t]/, "", t); if (t == "-") n++ } END { print n + 0 }')
  if [ "$_creep" -gt 0 ]; then
    printf '### %s hunk(s) in this commit served no task\n\n' "$_creep"
    printf 'The manifest says so itself. They were committed anyway, which was\n'
    printf 'the developer'"'"'s call -- but unrequested code is code nobody framed,\n'
    printf 'and it is the first place to look for a defect.\n\n'
  fi
)
[ -n "$_sig" ] || _sig="Nothing flagged. That is not a clean bill of health — it
means no grep matched, and every grep here is shallow by design."

# ----------------------------------------------------------------- write ---
tmpl_has review.md || die "missing template: review.md"

mkdir -p "$REVIEWS"
# The same awk substitution `leo task` uses, and for the same reason: these
# values are commit subjects and diff excerpts, and a `&` or a `\` in one of
# them would silently corrupt a sed replacement.
tmpl_cat review.md | \
LEO_REV="$_sha" \
LEO_SUBJECT="$_subject" \
LEO_CONTEXT="$_ctx" \
LEO_SIGNALS="$_sig" awk '
  function rep(str, from, to,   out, i) {
    while ((i = index(str, from)) > 0) {
      out = out substr(str, 1, i - 1) to
      str = substr(str, i + length(from))
    }
    return out str
  }
  { line = $0
    line = rep(line, "<REV>",     ENVIRON["LEO_REV"])
    line = rep(line, "<SUBJECT>", ENVIRON["LEO_SUBJECT"])
    if      (line == "<CONTEXT>") { print ENVIRON["LEO_CONTEXT"] }
    else if (line == "<SIGNALS>") { print ENVIRON["LEO_SIGNALS"] }
    else                          { print line }
  }' > "$_f"

_nfiles=$(printf '%s\n' "$_files" | grep -c . || true)
ok "opened ${_f#"$ROOT"/} — $_sha, ${_nfiles:-0} file(s)"
info ""
info "Read, in this order:"
dim  "  1. the \"What was asked for\" section — what the dev cycle recorded"
dim  "  2. .leo/review/STANDARDS.md — what a finding here has to clear"
dim  "  3. $([ "$_range" -eq 1 ] && printf 'git diff %s' "$_rev" || printf 'git show %s' "$_sha") — the code, against both"
info ""
dim  "Then fill the findings table, write the verdict, and: leo review --close"
dim  "You cannot fix anything from here. A fix is a new dev cycle."
