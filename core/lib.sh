#!/usr/bin/env bash
# lib.sh — everything shared, in one file you can read in a minute.
#
# Portability: bash 3.2 (macOS ships it), POSIX coreutils, git. No jq, no node,
# no network, no `sed -i`, no GNU-only flags.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OFF=$(printf '\033[0m'); C_DIM=$(printf '\033[2m'); C_B=$(printf '\033[1m')
  C_RED=$(printf '\033[31m'); C_GRN=$(printf '\033[32m'); C_YEL=$(printf '\033[33m')
else
  C_OFF=; C_DIM=; C_B=; C_RED=; C_GRN=; C_YEL=
fi

say()  { printf '%s\n' "$*"; }
info() { printf '%s\n' "$*" >&2; }
dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF" >&2; }
head_() { printf '\n%s%s%s\n' "$C_B" "$*" "$C_OFF" >&2; }
ok()   { printf '%sok  %s %s\n' "$C_GRN" "$C_OFF" "$*" >&2; }
warn() { printf '%swarn%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
err()  { printf '%sERR %s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------- repo ----
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)

need_repo() {
  [ -n "$ROOT" ] || die "not inside a git repository (leo is built on git)"
}

# untracked — new files git can see, honouring .gitignore.
untracked() { git ls-files --others --exclude-standard 2>/dev/null; }

# base_index <base> — a scratch git index seeded from <base>, printed as a
# path. The caller deletes it.
#
# Why leo does not just use the real index: a `leo record` base is a tree
# object holding files that are still untracked in the developer's index, and
# `git diff <tree>` reports those as *deleted* -- the tree has them, the index
# does not. The first fix for that was for `leo record` to `git add -A`, which
# made the diff right and the repository wrong: an ordinary `git commit` after
# a record swept the whole recorded change into it, under that commit's
# message, and `leo commit` then had nothing left to land.
#
# Seeding a throwaway index from the base instead gets the same correct diff
# and never touches what the developer has staged. The index is theirs.
base_index() {
  _i=$(mktemp "${TMPDIR:-/tmp}/leo-idx.XXXXXX")
  rm -f "$_i"
  GIT_INDEX_FILE="$_i" git read-tree "${1:-HEAD}" 2>/dev/null || true
  printf '%s' "$_i"
}

# not_bookkeeping — drop leo's own plan files from a stream of paths.
#
# `.leo/plans/` is tracked, unlike everything else leo writes, because a plan
# is the reasoning behind a change and outlives it. That makes the plan and
# its task files show up in `git diff` like any other tracked file -- so the
# manifest demanded a row for the plan that the manifest is scoped by, with a
# "Why" and an "If deleted" for a document whose answer to both is "it is the
# question you are asking", and the budget measured the change against an
# estimate the change's own prose was inflating.
#
# The rule, stated once: **the plan describing a change is not part of the
# change it describes.** Nothing else under `.leo/` is excluded. `.leo/rules/`
# and `.leo/integrations/` are repository code somebody wrote on purpose, they
# are reviewed like any other file, and a blanket `.leo/` filter here would
# quietly stop reviewing them.
not_bookkeeping() { grep -v '^\.leo/plans/' || true; }

# changed <base> — every file that differs from <base>, plus files that did not
# exist in it at all.
changed() {
  _b="${1:-HEAD}"
  _idx=$(base_index "$_b")
  { GIT_INDEX_FILE="$_idx" git diff --name-only "$_b" 2>/dev/null
    GIT_INDEX_FILE="$_idx" untracked
  } | sed '/^$/d' | not_bookkeeping | sort -u
  rm -f "$_idx"
}

# is_text <file> — false for binaries, so build output never gets line-counted.
# grep -I reports no match for a binary file on both GNU and BSD.
# is_text <file> — is this something a human reads, and leo should count lines
# of? `grep -I` is the binary test; the pattern is what decides the edge cases.
#
# It was `grep -Iq .`, and `.` needs one character on some line. A zero-byte
# file therefore matched nothing and was reported as binary -- which meant
# every empty `__init__.py` in a Python project arrived in the manifest as
# `binary`, with no line count and nothing to review. A file of only blank
# lines had the same problem. The empty pattern matches any line at all, and
# the -s guard covers the file that has no lines to match.
is_text() { [ ! -s "$1" ] || grep -Iq '' "$1" 2>/dev/null; }

# lines_changed <base> — added + removed across tracked and untracked files.
# git reports binary diffs as "-", which the awk drops; untracked binaries are
# excluded the same way batch_text_lines excludes them.
lines_changed() {
  _b="${1:-HEAD}"
  _idx=$(base_index "$_b")
  # The numstat is filtered on its third field and the untracked list on its
  # only one, so the same exclusion applies to both halves. See changed().
  { GIT_INDEX_FILE="$_idx" git diff --numstat "$_b" 2>/dev/null \
      | awk -F'\t' '$3 !~ /^\.leo\/plans\//'
    GIT_INDEX_FILE="$_idx" untracked | not_bookkeeping | batch_text_lines
  } | awk '$1 != "-" { n += $1 + $2 } END { print n + 0 }'
  rm -f "$_idx"
}

# batch_text_lines — read paths on stdin, print "lines<TAB>0<TAB>path" for
# every one that is text (binary and empty files silently contribute nothing,
# which is the same as contributing zero), the numstat format lines_changed's
# final awk already expects.
#
# This used to be `grep -Iq` then `wc -l`, once per path, in a plain
# `while read` loop -- two process spawns per untracked file. Invisible on a
# handful of files. Measured at ~8s against 3000 untracked files on a fast
# Mac, because spawning is not free even there, and it is what turned into a
# multi-minute leo on a Windows machine with a large untracked tree: process
# creation on Windows crosses into Win32 through MSYS's emulation layer, and
# costs far more per spawn than it does natively. `leo check` was completing
# in seconds on macOS and not completing in five minutes on Windows against
# comparable repositories, which is what a per-file spawn cost look like once
# it is multiplied by thousands of files and by a slower spawn.
#
# The fix is batching: hand `grep` and `wc` many paths per invocation instead
# of one. Not via `xargs`, whose default delimiter is any whitespace and
# would split "my file.txt" into two arguments -- `xargs -d '\n'` fixes that
# on GNU but does not exist on the `xargs` macOS ships, and this project does
# not take GNU-only flags. A bash array does not have that problem: each
# element is one argument regardless of what is inside it. The batch size is
# what keeps `"${_batch[@]}"` under a command-line length every platform here
# accepts, Windows included.
batch_text_lines() {
  _bt_batch=()
  _bt_flush() {
    [ "${#_bt_batch[@]}" -gt 0 ] || return 0
    _bt_text=$(grep -Il '' "${_bt_batch[@]}" 2>/dev/null || true)
    if [ -n "$_bt_text" ]; then
      _bt_files=()
      while IFS= read -r _bt_f; do _bt_files+=("$_bt_f"); done <<EOF_BT
$_bt_text
EOF_BT
      wc -l "${_bt_files[@]}" 2>/dev/null | grep -v ' total$' \
        | awk '{ n = $1; sub(/^ *[^ ]+ +/, ""); printf "%s\t0\t%s\n", n, $0 }'
    fi
    _bt_batch=()
  }
  while IFS= read -r _bt_p; do
    _bt_batch+=("$_bt_p")
    [ "${#_bt_batch[@]}" -ge 50 ] && _bt_flush
  done
  _bt_flush
}


now() { date -u '+%Y-%m-%d %H:%M UTC'; }

# ---------------------------------------------------------- line endings ----
# One carriage return, computed once, so nothing below has to embed a literal
# one in a pattern where it is invisible to whoever reads the code next.
CR=$(printf '\r')

# has_cr <file> — does this file have Windows line endings?
has_cr() { [ -f "$1" ] && LC_ALL=C grep -q "$CR" "$1" 2>/dev/null; }

# load_shell <file> — source a file leo treats as shell, surviving CRLF.
#
# `.leo/config` and `.leo/session` are plain `KEY=value` shell precisely so
# they need no parser. That is still true, and it is exactly why a carriage
# return is so destructive here: `TEST_CMD="npm test"` saved by Notepad sets
# the variable to `npm test` followed by a CR, and `leo check` then reports
#
#     ERR  npm test failed
#     command not found
#
# ...about a command that is installed and works. The developer is looking at
# a correct-looking file and an error blaming their test runner, with nothing
# on screen to connect the two. `MODE=coding` is worse, because it does not
# fail: `mode_policy` matches `coding` and never `coding\r`, so every
# capability silently falls through to its adapter default and the declared
# mode governs nothing at all.
#
# .gitattributes stops this for anything that arrives through git. It cannot
# stop a developer editing their own `.leo/config` in an editor that defaults
# to CRLF, which on Windows is most of them.
#
# The CR check comes first so the common case costs one grep rather than a
# mktemp, a tr and a temp file on every single leo invocation.
load_shell() {
  [ -f "$1" ] || return 0
  if has_cr "$1"; then
    _ls_tmp=$(mktemp "${TMPDIR:-/tmp}/leo-src.XXXXXX" 2>/dev/null) || return 0
    tr -d "$CR" < "$1" > "$_ls_tmp"
    # shellcheck disable=SC1090
    . "$_ls_tmp"
    rm -f "$_ls_tmp"
  else
    # shellcheck disable=SC1090
    . "$1"
  fi
}

# -------------------------------------------------------------- assets ----
# Everything leo reads out of its own install goes through here: the version
# and the templates. A single-file build (`leo build`) emits these same three
# functions with the content compiled in, sets LEO_BUNDLED, and this block then
# does not run -- so a bundle answers from itself and never looks for a source
# tree that is not next to it.
#
# The guard is what keeps the two builds honest. There is exactly one caller
# for each asset in either build; the source tree cannot grow a direct
# "$LEO_HOME/templates/..." read without the bundle losing it silently, because
# ASSET-SEAM fails the check when it does.
if [ -z "${LEO_BUNDLED:-}" ]; then
  leo_version() { cat "$LEO_HOME/VERSION"; }
  tmpl_has()    { [ -f "$LEO_HOME/templates/$1" ]; }
  tmpl_cat()    { cat "$LEO_HOME/templates/$1"; }
fi

# ------------------------------------------------------------- layout ----
# Everything leo owns lives under .leo/. One directory, no surprises.
LEO_DIR="${ROOT:-.}/.leo"
MANIFEST="$LEO_DIR/manifest.md"
RULES="$LEO_DIR/rules"
# One file per recorded-but-unlanded cycle. `leo record` writes them, `leo
# commit` reads them all and consumes them. See the records section below.
RECORDS="$LEO_DIR/commits"
# Which declared tools this cycle actually used. `leo use` appends, `leo check`
# reads, `leo record` folds it into the record and clears it. See the tools
# section below.
USED="$LEO_DIR/used"

# ------------------------------------------------------- plan registry ----
# A change is one plan. A repository has many of them, because the developer
# comes back a week later wanting something else and the old plan is not
# wrong, it is finished -- or deferred, which is the same shape.
#
#   .leo/plans/P1/plan.md        the change: goal, non-goals, tasks, budget
#   .leo/plans/P1/tasks/T1.md    one file per task -- its grill, its to-do
#   .leo/current                 which plan the work is in, one line
#
# Task ids do not restart. P1 owns T1..T3, P2 starts at T4, and no id is ever
# reused. A manifest row says `T4` and means exactly one task in exactly one
# plan, forever -- which is the property the whole manifest rests on, and the
# one a per-plan counter would quietly destroy the day two plans both had a T1
# and `git log` could no longer tell them apart.
PLANS="$LEO_DIR/plans"
CURRENT="$LEO_DIR/current"

# plan_id — the plan in flight, or empty. One line, no parsing.
plan_id() {
  [ -f "$CURRENT" ] || return 0
  head -1 "$CURRENT" 2>/dev/null | tr -d ' \t\n'
}

plan_path() { printf '%s/%s/plan.md' "$PLANS" "$1"; }

# The active plan, and where its task files live. Resolved once, here, so no
# command has to know the registry exists.
#
# The fallback is not legacy debt, it is the single-plan repository: a .leo/
# with a plan.md and no plans/ is what every leo before this wrote, and what
# `printf ... > .leo/plan.md` still writes in a test. It keeps working, it is
# never migrated behind anyone's back, and `leo plan --list` names it `legacy`
# so it can be switched back to.
_pid=$(plan_id)
if [ -n "$_pid" ] && [ "$_pid" != "legacy" ] && [ -f "$(plan_path "$_pid")" ]; then
  PLAN="$(plan_path "$_pid")"
  TASKS="$PLANS/$_pid/tasks"
else
  PLAN="$LEO_DIR/plan.md"
  TASKS="$LEO_DIR/tasks"
fi
unset _pid

# plan_use <id> — re-point PLAN and TASKS at another plan, in this process.
#
# `leo plan --switch` writes .leo/current and then wants to print the new
# plan's status, and the exit hook wants to write SESSION.md about it. Both
# read $PLAN, which was resolved when lib.sh loaded -- from the old plan. The
# file on disk is right and everything printed afterwards is about the plan
# you just left.
plan_use() {
  if [ "$1" = "legacy" ]; then
    PLAN="$LEO_DIR/plan.md"; TASKS="$LEO_DIR/tasks"
  else
    PLAN="$(plan_path "$1")"; TASKS="$PLANS/$1/tasks"
  fi
}

# plans_list — every numbered plan, lowest first. `sort -t P -k2 -n` rather
# than a plain sort: P10 sorts before P2 as a string, and the order these are
# printed in is the order the work happened in.
plans_list() {
  [ -d "$PLANS" ] || return 0
  for _p in "$PLANS"/P*/plan.md; do
    [ -f "$_p" ] || continue
    _d=$(dirname "$_p"); basename "$_d"
  done | sort -t P -k2 -n
}

# plan_next_id — the id a new plan gets. Highest existing plus one, never a
# count: deleting P2 must not make the next plan P2 again and inherit its
# history in anyone's memory.
plan_next_id() {
  _max=0
  for _p in $(plans_list); do
    _n=${_p#P}
    case "$_n" in ''|*[!0-9]*) continue ;; esac
    [ "$_n" -gt "$_max" ] && _max="$_n"
  done
  printf 'P%d' $(( _max + 1 ))
}

# plan_file_tasks <plan.md> — the task ids one plan file declares.
plan_file_tasks() {
  [ -f "$1" ] || return 0
  awk -F'|' '/^\| *T[0-9]/ { id = $2; gsub(/[ \t]/, "", id); print id }' "$1"
}

# task_next_n — the number the next task gets, across every plan and the
# legacy one. This is what makes P2 start at T4 instead of at T1.
task_next_n() {
  _max=0
  for _p in $(plans_list); do
    _f=$(plan_path "$_p")
    for _t in $(plan_file_tasks "$_f"); do
      _n=${_t#T}; _n=${_n%%.*}
      case "$_n" in ''|*[!0-9]*) continue ;; esac
      [ "$_n" -gt "$_max" ] && _max="$_n"
    done
  done
  for _t in $(plan_file_tasks "$LEO_DIR/plan.md"); do
    _n=${_t#T}; _n=${_n%%.*}
    case "$_n" in ''|*[!0-9]*) continue ;; esac
    [ "$_n" -gt "$_max" ] && _max="$_n"
  done
  printf '%d' $(( _max + 1 ))
}

# task_owner <id> — which plan declares this task, or empty. The point is the
# error message: "T2 is not in the plan" is true and useless when T2 is in P1
# and you are standing in P2.
task_owner() {
  for _p in $(plans_list); do
    plan_file_tasks "$(plan_path "$_p")" | grep -qx "$1" && { printf '%s' "$_p"; return 0; }
  done
  plan_file_tasks "$LEO_DIR/plan.md" | grep -qx "$1" && printf 'legacy'
  return 0
}

# .leo/config is plain `KEY=value` shell so it needs no parser.
TEST_CMD=""
load_shell "$LEO_DIR/config"

# plan_est — the LOC estimate declared in the plan, or empty.
# The trailing `|| true` matters: a plan with no estimate is a normal state, but
# a failing grep inside $( ) under `set -e` would take the caller down with it.
plan_est() {
  [ -f "$PLAN" ] || return 0
  grep -i '^est:' "$PLAN" 2>/dev/null | grep -o '[0-9][0-9]*' | head -1 || true
}

# plan_status — "2 of 5 done  |  in progress: T3", or empty when the plan
# declares no tasks. Both `leo plan` and the session report ask this, and a
# second copy of the awk would drift from the first the day someone renames a
# status.
plan_status() {
  [ -f "$PLAN" ] || return 0
  awk -F'|' '
    /^\| *T[0-9]/ {
      id = $2; gsub(/[ \t]/, "", id)
      st = $6; gsub(/[ \t]/, "", st)
      total++
      if (st == "done") { done++ }
      else if (st == "later") { later++ }
      else if (st == "in-progress") { doing = doing (doing ? "," : "") id }
      else if (next_ == "") { next_ = id }
    }
    END {
      if (!total) exit
      printf "%d of %d done", done + 0, total
      if (later + 0)  printf ", %d later", later
      if (doing != "") printf "  |  in progress: %s", doing
      else if (next_ != "") printf "  |  next: %s", next_
      else if (later + 0) printf "  |  nothing left but later work"
    }' "$PLAN"
}

# ------------------------------------------------------------- tasks ----
# A task file is .leo/tasks/T1.md: what is left inside one plan row. The plan
# stays the authority for whether a task is done, and these helpers read it
# rather than storing a second copy -- the duplication this whole stage is most
# likely to grow by accident.
#
# Every one of them guards its read. A substitution over a missing file under
# `set -e` with `pipefail` takes the caller down after the value was already
# computed, which is the failure lines_changed above documents at length.
# TASKS is set in the plan registry above: it is the active plan's directory,
# not a fixed path, and setting it twice is how the second one goes stale.

task_file() { printf '%s/%s.md' "$TASKS" "$1"; }

# plan_tasks — every task id the plan declares, in order.
plan_tasks() {
  [ -f "$PLAN" ] || return 0
  awk -F'|' '/^\| *T[0-9]/ { id = $2; gsub(/[ \t]/, "", id); print id }' "$PLAN"
}

plan_has_task() {
  plan_tasks | grep -qx "$1"
}

# _plan_field <id> <column> — one cell of a task's row. The column numbers are
# the plan template's: 2 id, 3 name, 4 files, 5 est, 6 status.
_plan_field() {
  [ -f "$PLAN" ] || return 0
  awk -F'|' -v want="$1" -v col="$2" '
    /^\| *T[0-9]/ {
      id = $2; gsub(/[ \t]/, "", id)
      if (id == want) {
        v = $col
        gsub(/^[ \t]+|[ \t]+$/, "", v)
        print v
        exit
      }
    }' "$PLAN"
}

plan_task_name()   { _plan_field "$1" 3; }
plan_task_files()  { _plan_field "$1" 4; }
plan_task_est()    { _plan_field "$1" 5; }
plan_task_status() { _plan_field "$1" 6; }

# task_todo <id> — "3/5", or empty when there is no task file. Counts the
# checkboxes and nothing else, so a to-do written in prose reports nothing
# rather than a wrong number.
task_todo() {
  _tf=$(task_file "$1")
  [ -f "$_tf" ] || return 0
  awk '
    /^- \[[xX]\]/  { d++ }
    /^- \[[ xX]\]/ { t++ }
    END { if (t) printf "%d/%d", d + 0, t }' "$_tf"
}

# task_current — the task the work is on: the in-progress one, else the first
# that is not done. Empty when the plan declares none.
# awk runs END on `exit`, so "print and exit" prints a second time from END.
# That is why this sets a variable and prints once, in END, instead: a pending
# task ahead of an in-progress one used to return both ids, and next_step then
# built a task-file path with a newline in the middle of it.
task_current() {
  [ -f "$PLAN" ] || return 0
  awk -F'|' '
    /^\| *T[0-9]/ {
      id = $2; gsub(/[ \t]/, "", id)
      st = $6; gsub(/[ \t]/, "", st)
      # "later" is skipped exactly as "done" is. That is the whole feature:
      # the work is not finished and is not in the way, so the loop steps over
      # it and the next task becomes the task in flight. A deferred task that
      # still answered task_current would keep `leo check` demanding a grill
      # for work nobody intends to do this week.
      if (st == "in-progress" && doing == "") doing = id
      if (st != "done" && st != "later" && first == "") first = id
    }
    END { if (doing != "") print doing; else if (first != "") print first }' "$PLAN"
}

# plan_later — every task the plan has deferred, space separated. Read by the
# report, the record and the check, so "what did we put off" has one answer.
plan_later() {
  [ -f "$PLAN" ] || return 0
  awk -F'|' '
    /^\| *T[0-9]/ {
      id = $2; gsub(/[ \t]/, "", id)
      st = $6; gsub(/[ \t]/, "", st)
      if (st == "later") out = out (out ? " " : "") id
    }
    END { if (out != "") print out }' "$PLAN"
}

# plan_later_why <id> — the reason `leo defer` wrote under "## Later", or
# empty. The status cell says a task is deferred; only this says why, and a
# deferral with no why is indistinguishable from one that was forgotten.
plan_later_why() {
  [ -f "$PLAN" ] || return 0
  awk -v want="$1" '
    /^## Later/ { inx = 1; next }
    inx && /^## / { exit }
    inx && /^- / {
      line = $0
      sub(/^- /, "", line)
      id = line; sub(/ .*$/, "", id)
      if (id == want) {
        # Strip the id, then everything up to the first word. The separator is
        # an em dash and byte-wise character classes do not reliably match one
        # -- the same reason review_subject does it this way.
        sub(/^[^ ]*/, "", line)
        sub(/^[^A-Za-z0-9]*/, "", line)
        print line; exit
      }
    }' "$PLAN"
}

# ------------------------------------------------------------- subtasks ----
# A subtask is a `## T1.2 <name>` heading inside its parent's file. It can be
# deferred too, and the mark is a `Status: later` line directly under the
# heading -- the same shape as the plan's status cell, one level down.

# subtask_ids <task-id> — every subtask heading in a task file, in order.
subtask_ids() {
  _tf=$(task_file "$1")
  [ -f "$_tf" ] || return 0
  awk -v p="$1" '$1 == "##" && index($2, p ".") == 1 { print $2 }' "$_tf"
}

# subtask_state <task-id> <subtask-id> — "later" or empty.
subtask_state() {
  _tf=$(task_file "$1")
  [ -f "$_tf" ] || return 0
  awk -v want="$2" '
    $1 == "##" { here = ($2 == want) }
    here && /^Status: *later/ { print "later"; exit }' "$_tf"
}

# task_later_subs <task-id> — the deferred subtasks of one task.
task_later_subs() {
  for _s in $(subtask_ids "$1"); do
    [ "$(subtask_state "$1" "$_s")" = "later" ] && printf '%s ' "$_s"
  done
  return 0
}

# task_ungrilled <task-id> — how many sections of this task still carry the
# ungrilled marker, NOT counting deferred ones.
#
# The exclusion is the point. A subtask that has been put off has not been
# grilled and must not be: grilling it would mean answering questions about
# work that is not happening, and the answers would be guesses. Counting it
# would make `leo check` unpassable until somebody either did the work or
# deleted the subtask, which is exactly the pressure that gets deferrals
# deleted instead of recorded.
task_ungrilled() {
  _tf=$(task_file "$1")
  [ -f "$_tf" ] || { printf 0; return 0; }
  awk '
    /^## /            { later = 0 }
    /^Status: *later/ { later = 1 }
    /leo:ungrilled/   { if (!later) n++ }
    END { print n + 0 }' "$_tf"
}

# plan_name — the change this plan is for, from its title line.
plan_name() {
  [ -f "$PLAN" ] || return 0
  sed -n 's/^# Plan: *//p' "$PLAN" | head -1
}

# next_step — which of the six stages this change is in, as the command that
# advances it. Derived from the plan, the task files, the manifest and git, all
# of which are already on disk: nothing is stored to make this printable, and
# no command refuses to run because of what this returns. It is a reminder, not
# a gate.
#
# grill me -> plan -> task creation -> build -> manifest -> commit suggestion
next_step() {
  [ -f "$PLAN" ] || {
    printf 'grill the developer, then: leo plan "<name>"'
    return 0
  }

  _t=$(task_current)
  if [ -n "$_t" ]; then
    _tf=$(task_file "$_t")
    if [ ! -f "$_tf" ]; then
      printf 'leo task %s' "$_t"
      return 0
    fi
    _td=$(task_todo "$_t")
    case "$_td" in
      "") ;;
      *)  _d=${_td%%/*}; _n=${_td##*/}
          if [ "$_d" -lt "$_n" ]; then
            printf 'build %s — next: %s' "$_t" "$(task_next_item "$_t")"
            return 0
          fi
          # Every box ticked but the plan still says otherwise. Without this
          # the reminder jumped to `leo scan` and the remaining tasks were
          # never built -- the status is what moves the work to the next task.
          if [ "$(plan_task_status "$_t")" != "done" ]; then
            printf 'set %s to done in .leo/plan.md' "$_t"
            return 0
          fi ;;
    esac
  fi

  # Every task either done or deferred, and nothing scanned. The change is
  # not finished, it is parked -- and saying "leo scan" here would send the
  # agent to build a manifest for work that was explicitly put off.
  if [ -z "$_t" ] && [ ! -f "$MANIFEST" ]; then
    _l=$(plan_later)
    if [ -n "$_l" ]; then
      printf 'every task left is later work (%s) — leo resume <id>, or leo plan "<next change>"' "$_l"
      return 0
    fi
  fi

  [ -f "$MANIFEST" ] || { printf 'leo scan'; return 0; }

  # A blank Task cell is a hunk nobody has accounted for yet, which is the
  # manifest stage rather than the check stage.
  _blank=$(awk -F'|' '
    /^\| *[0-9NEW]/ { t = $5; gsub(/[ \t]/, "", t); if (t == "") n++ }
    END { print n + 0 }' "$MANIFEST")
  [ "$_blank" -gt 0 ] && {
    printf 'fill the manifest — %s hunk(s) name no task' "$_blank"
    return 0
  }

  # The cycle ends at the record, not at the commit. `leo commit` is still the
  # developer's and still lands the change -- it is just no longer the thing
  # that has to happen for this cycle to be finished.
  printf 'leo check, then leo record "<subject>" — the commit comes later, and is theirs'
}

# task_next_item <id> — the first unticked line of a task's to-do, trimmed, so
# the reminder can name the actual next thing rather than "keep going".
task_next_item() {
  _tf=$(task_file "$1")
  [ -f "$_tf" ] || return 0
  awk '
    /^- \[ \]/ {
      sub(/^- \[ \][ \t]*/, "")
      print
      exit
    }' "$_tf"
}

# who — best-effort agent name for the commit trailer, so provenance is
# recorded without anyone configuring anything.
who() {
  if   [ -n "${LEO_AGENT:-}" ];      then printf '%s' "$LEO_AGENT"
  elif [ -n "${CLAUDECODE:-}" ];     then printf 'Claude Code'
  elif [ -n "${CURSOR_TRACE_ID:-}" ];then printf 'Cursor'
  elif [ -n "${CODEX_HOME:-}" ];     then printf 'Codex'
  elif [ -n "${AIDER_MODEL:-}" ];    then printf 'Aider'
  else printf 'unknown'
  fi
}

# ------------------------------------------------------------ records ----
# A recorded commit message that has not landed yet. `leo record` writes one
# per finished cycle; `leo commit` folds every one of them into a single real
# commit and deletes them.
#
# The point is that a cycle can finish -- checked, manifested, message written
# -- without the developer having to decide the *whole* change is done. That
# decision was being asked several times for what is really one piece of work,
# and each early yes spent a commit on a change nobody had seen whole yet.
#
# Records are working state, like the plan and the manifest: they are
# gitignored, because every one of them ends up inside the commit message it
# describes.

# records — every record file, oldest first. Silent when there are none.
records() {
  [ -d "$RECORDS" ] || return 0
  # A literal glob is what `ls` returns for an empty directory; the guard is
  # what keeps a "leo/commits/*.md" from being read as a filename.
  for _r in "$RECORDS"/*.md; do
    [ -f "$_r" ] || continue
    printf '%s\n' "$_r"
  done
}

# record_count — how many cycles are recorded and waiting.
record_count() { records | wc -l | tr -d ' '; }

# record_next_id — the number the next record gets, zero-padded so the glob
# above sorts in the order the cycles actually happened.
record_next_id() {
  _n=$(records | wc -l | tr -d ' ')
  printf '%03d' $(( _n + 1 ))
}

# record_field <file> <name> — one `Name: value` header line from a record.
record_field() {
  sed -n "s/^$2: *//p" "$1" | head -1
}

# record_base — what the next `leo scan` should diff against.
#
# Without a landed commit there is no HEAD that means "everything before this
# cycle", so each record carries the tree it left behind and the next scan
# starts from that. Otherwise cycle two's manifest would re-enumerate every
# hunk cycle one already accounted for, and the budget check would measure the
# whole change against one task's estimate.
record_base() {
  _last=$(records | tail -1)
  [ -n "$_last" ] || { printf 'HEAD'; return 0; }
  _t=$(record_field "$_last" Tree)
  # A tree object is not reachable from any ref, so `git gc --prune=now` can
  # take it. That is a fortnight of grace by default and these live for hours,
  # but fall back rather than die on a base that has been collected.
  if [ -n "$_t" ] && git rev-parse --verify --quiet "$_t" >/dev/null 2>&1; then
    printf '%s' "$_t"
  else
    printf 'HEAD'
  fi
}

# snapshot_tree — write the working tree as a git tree object and print its
# sha, without touching the developer's index.
#
# The staging version of this made `git diff <tree>` work and the repository
# wrong; see base_index for what that cost. Everything that reads one of these
# trees goes through base_index, so the snapshot can stay in a throwaway index
# where it belongs.
snapshot_tree() {
  _i=$(mktemp "${TMPDIR:-/tmp}/leo-snap.XXXXXX")
  rm -f "$_i"
  GIT_INDEX_FILE="$_i" git read-tree HEAD 2>/dev/null || true
  GIT_INDEX_FILE="$_i" git add -A
  GIT_INDEX_FILE="$_i" git write-tree
  rm -f "$_i"
}

# ------------------------------------------------------------ reviews ----
# Cycle two. `.leo/reviews/<sha>.md` is one review of one commit that has
# already landed, and unlike the plan and the manifest it is *tracked*: those
# two end up inside the commit message they describe, and a review of an
# existing commit has nowhere to go but the repository. A record with no home
# is a record nobody reads.
#
# The findings table is the only machine-readable part, and only two of its
# columns are read: severity and status. Both vocabularies are closed, which
# is what `leo review --close` checks first -- a status leo cannot parse is a
# finding nobody dispositioned, and it must not pass by being unreadable.
REVIEWS="$LEO_DIR/reviews"

# review_count <file> [severity] [status] — findings matching, or all of them.
review_count() {
  [ -f "$1" ] || { printf 0; return 0; }
  awk -F'|' -v ws="${2:-}" -v wt="${3:-}" '
    /^\| *[0-9]/ {
      s = $3; gsub(/[ \t`]/, "", s)
      t = $7; gsub(/[ \t`]/, "", t)
      if (ws != "" && s != ws) next
      if (wt != "" && t != wt) next
      n++
    }
    END { print n + 0 }' "$1"
}

review_verdict() {
  [ -f "$1" ] || return 0
  sed -n 's/^Verdict: *//p' "$1" | head -1
}

# review_subject <file> — the reviewed commit's subject, off the title line.
# awk rather than sed: the separator is an em dash, and byte-wise sed classes
# do not reliably match one.
review_subject() {
  [ -f "$1" ] || return 0
  awk 'NR == 1 {
         sub(/^# Review: */, "")
         i = index($0, " "); if (i) $0 = substr($0, i + 1)
         sub(/^[^A-Za-z0-9]*/, "")
         print; exit
       }' "$1"
}

# review_closed <file> — the stamp `--close` writes, or empty/"-" while open.
review_closed() {
  [ -f "$1" ] || return 0
  sed -n 's/^Closed: *//p' "$1" | head -1
}

# review_state <file> — closed once stamped; ready when the findings are all
# dispositioned and the verdict is real; open until then.
#
# "Ready" and "closed" are deliberately two things. They were one at first,
# derived from the same content, and the result was a review that could never
# be closed: the moment it satisfied the conditions it stopped looking like
# something waiting to be closed, and `--close` could no longer find it. The
# stamp is the difference between "nothing is outstanding" and "someone said
# so", which is the same difference the whole tool is built on.
review_state() {
  [ -f "$1" ] || { printf 'missing'; return 0; }
  case "$(review_closed "$1")" in
    ""|-|*"<"*) ;;
    *) printf 'closed'; return 0 ;;
  esac
  case "$(review_verdict "$1")" in
    ""|*"<"*) printf 'open'; return 0 ;;
  esac
  if [ "$(review_count "$1" blocker open)" -gt 0 ]; then printf 'open'; return 0; fi
  printf 'ready'
}
review_pick() {
  if [ -n "${1:-}" ]; then
    _p="$REVIEWS/$1.md"
    if [ ! -f "$_p" ]; then
      _s=$(git rev-parse --short "$1" 2>/dev/null || true)
      [ -n "$_s" ] && _p="$REVIEWS/$_s.md"
    fi
    [ -f "$_p" ] || { err "no review for $1 — open one: leo review $1"; return 1; }
    printf '%s' "$_p"; return 0
  fi
  _open=""
  for _r in "$REVIEWS"/*.md; do
    [ -f "$_r" ] || continue
    [ "$(review_state "$_r")" = "closed" ] || _open="$_open $_r"
  done
  # shellcheck disable=SC2086
  set -- $_open
  case $# in
    0) err "no open review — open one: leo review <rev>"; return 1 ;;
    1) printf '%s' "$1"; return 0 ;;
    *) err "$# reviews are open — name one: leo review --close <rev>"
       for _r in "$@"; do dim "  $(basename "$_r" .md)"; done
       return 1 ;;
  esac
}

# ------------------------------------------------------------ session ----
# .leo/session declares what kind of work this change is, and which agent
# capabilities that kind of work wants. Plain `KEY=value` shell, like
# .leo/config, so it needs no parser.
#
# It was a declaration and not a switch: leo recorded what was mediating the
# agent's view and checked nothing. That made the switches decorative -- six of
# the seven capabilities changed no leo behaviour at all, on or off, so a mode
# was a label rather than a setting.
#
# It is a switch now, enforced the only way leo can enforce anything: not by
# controlling the agent, which it cannot do, but by requiring evidence. ON must
# leave a mark, OFF must leave none, and `leo check` reads both. leo still
# installs, launches and configures nothing.
#
# Engineering controls are deliberately absent. Plan, task IDs, manifest,
# rules, tests and human commit live in the code that runs them, so there is no
# key here that could turn one off.
SESSION="$LEO_DIR/session"

# The capabilities leo ships with, in display order. Extensions are appended to
# this by cap_discover below; nothing here is positional any more.
BUILTIN_CAPS="serena graph rtk headroom ponytail caveman tdd"

MODE=""
load_shell "$SESSION"

# mode_policy <mode> — the built-in default for each capability, as name=state
# pairs. Empty for a mode leo does not know, which is how the caller validates
# one. A capability missing from a row falls through to its adapter's own
# <cap>_default, and then to off.
#
# Named rather than positional. The first version returned bare on/off values
# lined up with the CAPS string, which meant reordering one line silently
# remapped every mode -- and it could not express a capability leo had never
# heard of, which is exactly what an extension is.
#
# Debugging, learning and exploration turn the semantic reducers off: during
# those, the thing that matters is often the thing that looks like noise. RTK
# stays on throughout because its filtering is structural (progress bars,
# repeated lines) rather than a model deciding what you needed to see.
mode_policy() {
  case "$1" in
    coding)      echo "serena=on graph=off rtk=on headroom=on  ponytail=on  caveman=off tdd=on"  ;;
    debugging)   echo "serena=on graph=on  rtk=on headroom=off ponytail=off caveman=off tdd=on"  ;;
    learning)    echo "serena=on graph=on  rtk=on headroom=off ponytail=off caveman=off tdd=off" ;;
    review)      echo "serena=on graph=on  rtk=on headroom=on  ponytail=off caveman=off tdd=off" ;;
    exploration) echo "serena=on graph=on  rtk=on headroom=off ponytail=off caveman=off tdd=off" ;;
  esac
}

MODES="coding debugging learning review exploration"

# cap_over <cap> — the explicit override for a capability, or empty. An
# override is stored uppercased, so `--caveman on` is CAVEMAN=on in the file.
cap_over() {
  _u=$(printf '%s' "$1" | tr 'a-z' 'A-Z')
  printf '%s' "${!_u:-}"
}

# cap_state <cap> — what it is actually set to: the override if there is one,
# otherwise the mode's default. Empty when there is no session at all.
# cap_state <cap> — what it is actually set to. In order: an explicit override,
# the mode's built-in default, the adapter's own default, then off. Empty when
# there is no session at all.
cap_state() {
  [ -n "$MODE" ] || return 0
  _o=$(cap_over "$1")
  [ -n "$_o" ] && { printf '%s' "$_o"; return 0; }
  for _p in $(mode_policy "$MODE"); do
    case "$_p" in "$1"=*) printf '%s' "${_p#*=}"; return 0 ;; esac
  done
  if command -v "${1}_default" >/dev/null 2>&1; then
    printf '%s' "$("${1}_default" "$MODE")"
    return 0
  fi
  printf 'off'
}

# session_desc — "debugging (caveman=on)" for the commit trailer, or empty.
# Only the overrides are named: a default is the mode, and the mode is already
# there. What a reviewer needs is the part the developer changed by hand.
session_desc() {
  [ -n "$MODE" ] || return 0
  _d=""
  for _c in $CAPS; do
    _o=$(cap_over "$_c")
    [ -n "$_o" ] && _d="$_d${_d:+, }$_c=$_o"
  done
  printf '%s%s' "$MODE" "${_d:+ ($_d)}"
}

# ------------------------------------------------------- integrations ----
# An adapter is a file in core/integrations/ that defines three functions and
# nothing else. No registry, same as commands:
#
#   <cap>_present   exit 0 if the tool is installed
#   <cap>_hint      print how to install it
#   <cap>_advice    print what the agent should do when it is on
#
# Adapters never install, launch, wrap or configure anything. leo has no
# runtime dependency on any tool it can name, and adding one here must not
# create one. If an adapter ever needs to write outside .leo/, it is the wrong
# shape and belongs in the developer's own setup.
# Two directories, in this order: leo's own, then the repository's. A repo
# adapter with the same name as a built-in is sourced second and wins, so a
# team whose environment needs a different install command does not have to
# fork leo to get one.
#
# `.leo/integrations/` is repository code that leo sources, exactly as
# `.leo/config` already is and `.leo/rules/*.md` already are. Read an unfamiliar
# repository's `.leo/` before running leo in it, the same as you would its
# Makefile.
# In a bundle the built-in adapters are already defined as functions and there
# is no directory to glob, so only the repository's own dir is listed. Dropping
# it entirely would be the easy bug: a bundle that silently cannot load the
# adapters a team wrote for their own repo.
if [ -n "${LEO_BUNDLED:-}" ]; then
  ADAPTER_DIRS="${ROOT:+$ROOT/.leo/integrations}"
else
  ADAPTER_DIRS="$LEO_HOME/core/integrations${ROOT:+ $ROOT/.leo/integrations}"
fi

for _dir in $ADAPTER_DIRS; do
  for _adapter in "$_dir"/*.sh; do
    [ -f "$_adapter" ] || continue
    # A repository adapter is somebody else's file, and leo sources it on every
    # single command. One unbalanced quote in it would take down `leo check`
    # along with everything else -- so it is parsed first and skipped if it does
    # not compile. leo's own adapters skip the check: they are covered by
    # ADAPTER-CONTRACT and the smoke test, and this runs on every invocation.
    # Match the directory exactly, not a "$LEO_HOME"/* prefix: when leo is
    # installed in the repository it is being run from -- which is how leo is
    # developed -- every repo adapter matches that prefix and skips the check.
    case "$_dir" in
      "$LEO_HOME/core/integrations") ;;
      *) bash -n "$_adapter" 2>/dev/null || {
           printf 'warn %s does not parse — skipped\n' "$_adapter" >&2
           continue
         } ;;
    esac
    load_shell "$_adapter"
  done
done

# CAPS — the built-ins in display order, then whatever the repository added,
# in the order the shell globs them. Discovered from files rather than from a
# list, so adding a capability is dropping in a file: same as a command, same
# as a rule.
CAPS="$BUILTIN_CAPS"
for _dir in $ADAPTER_DIRS; do
  for _adapter in "$_dir"/*.sh; do
    [ -f "$_adapter" ] || continue
    _n=$(basename "$_adapter" .sh)
    # Only if it actually loaded. A file that was skipped above must not become
    # a capability, or leo names something it has no functions for.
    command -v "${_n}_present" >/dev/null 2>&1 || continue
    printf '%s\n' $CAPS | grep -qx "$_n" || CAPS="$CAPS $_n"
  done
done

# ------------------------------------------------------------- tools ----
# A switch is only a switch if something checks it. leo cannot make an agent
# call a tool or stop it calling one -- it is a shell script that runs before
# and after, not a supervisor. What it can do is the thing it already does for
# the grill: require the mark that using something leaves behind.
#
# Two kinds of tool, because they leave two different kinds of mark:
#
#   invoked   the agent calls it at a moment -- a code index, a graph query.
#             The mark is the agent saying so: `leo use serena` announces it
#             and writes the ledger, in one action, so what you see and what
#             the check reads cannot disagree.
#   ambient   an output filter or context reducer wrapping the whole session.
#             It is not used at a moment, it is in effect. The mark is the
#             adapter's own `_present`: on and not actually installed is a
#             failure of the environment, not of the agent's honesty.
#
# The honest limit, stated once and repeated in the docs: an agent that uses an
# invoked tool and never runs `leo use` is invisible to this. Attestation
# catches the careless case, not the deceptive one. It is still the difference
# between a switch and a label.

# cap_kind <cap> — invoked, ambient or practice. Ambient is the default: it
# needs nothing from the agent, so an adapter that never declares a kind cannot
# start failing checks for want of a line nobody knew to write.
cap_kind() {
  if command -v "${1}_kind" >/dev/null 2>&1; then
    "${1}_kind"
  else
    printf 'ambient'
  fi
}

# used_log <cap> [note] — record one tool use, once per cycle.
#
# Appended rather than rewritten, and deduplicated on the name: the question
# this answers is "which tools built these hunks", which one line each answers
# completely. A line per call would grow with the session and be re-read by the
# agent on every later turn, which is the cost `leo check` went terse to avoid.
used_log() {
  mkdir -p "$LEO_DIR"
  used_has "$1" && return 0
  printf '%s\t%s%s\n' "$1" "$(now)" "${2:+	$2}" >> "$USED"
}

# used_has <cap> — has this tool already been logged this cycle?
used_has() {
  [ -f "$USED" ] || return 1
  cut -f1 "$USED" | grep -qx "$1"
}

# used_note <cap> — the third field, when there is one. DENIED marks a tool
# that was refused and used anyway, which is the one thing here that fails a
# check rather than merely informing it.
used_note() {
  [ -f "$USED" ] || return 0
  awk -F'\t' -v c="$1" '$1 == c { print $3; exit }' "$USED"
}

# used_list — every tool logged this cycle, one name per line.
used_list() {
  [ -f "$USED" ] || return 0
  cut -f1 "$USED"
}

# cap_present <cap> — 0 installed, 1 missing, 2 leo has no adapter for it.
# The third case is real and must stay visible: leo can name a capability it
# cannot detect, and a display that showed that as "missing" would be lying
# about whose fault it is.
#
# The adapter's status is collapsed to 0 or 1 rather than passed through. 2 is
# leo's word, not the adapter's, and an adapter can return it by accident: a
# `_present` that ends in `grep -q pattern missing-file` returns 2, and the
# capability then reports as unsupported when it is merely not installed.
cap_present() {
  command -v "${1}_present" >/dev/null 2>&1 || return 2
  "${1}_present" && return 0
  return 1
}

# cap_call <cap> <hint|advice> — run an optional adapter function, silently
# doing nothing when the adapter does not define it.
cap_call() {
  command -v "${1}_$2" >/dev/null 2>&1 || return 0
  "${1}_$2"
}

# cap_label <cap> — the display name, from the adapter or from the name.
cap_label() {
  _l=$(cap_call "$1" label)
  printf '%s' "${_l:-$1}"
}

# cap_oneline <cap> — one line an agent can act on without opening anything.
# The adapter's own `<cap>_oneline` if it has one, otherwise the first line of
# its advice, otherwise nothing.
#
# One line, deliberately. This is what `leo agents` writes into AGENTS.md, and
# AGENTS.md is re-read on every request of every session forever -- see
# .leo/rules/ALWAYS-LOADED.md for what a paragraph here costs.
cap_oneline() {
  if command -v "${1}_oneline" >/dev/null 2>&1; then
    "${1}_oneline"
    return 0
  fi
  cap_call "$1" advice | head -1
}

# cap_mcp <cap> — the MCP tool names this capability exposes, or empty.
# Empty is a real answer and the common one: most of these are not MCP servers
# at all, and inventing names for them is how an agent ends up calling a tool
# that does not exist and concluding leo is broken.
cap_mcp() {
  command -v "${1}_mcp" >/dev/null 2>&1 || return 0
  "${1}_mcp"
}

# cap_signature — every fact about this session that an agent's instructions
# depend on, as one line. `leo agents` stamps a checksum of this into
# AGENTS.md; `leo agents --check` recomputes it.
#
# Installed state is in it on purpose. A tool that is ON and was installed
# since the block was written has different instructions -- the agent should
# be told to use it rather than told it is missing -- and a fingerprint over
# the switches alone would call that block current.
cap_signature() {
  printf 'mode=%s' "${MODE:-none}"
  for _c in $CAPS; do
    _rc=0; cap_present "$_c" >/dev/null 2>&1 || _rc=$?
    printf ' %s=%s/%s' "$_c" "$(cap_state "$_c")" "$_rc"
  done
  printf '\n'
}

# cap_fingerprint — cap_signature, short enough to sit in a comment. cksum is
# POSIX and everywhere; sha1sum is neither on macOS nor named the same thing
# when it is there.
cap_fingerprint() {
  cap_signature | cksum | tr -d ' ' | cut -c1-12
}

# ---------------------------------------------------------- exit hooks ----
# One EXIT trap for the whole tool, and a list of things to run in it.
#
# There used to be three traps -- lib.sh had none, `leo check` had one for its
# buffer, `leo build` had one for its temp file -- and `trap ... EXIT` does not
# stack: the last one installed silently replaces every earlier one. That is
# fine while the trap only deletes a temp file. It stops being fine the moment
# the trap has to write the session document, because the one command whose
# session document matters most (`leo check`, the one that fails) is precisely
# the command that was overwriting the trap.
#
# So: register, never trap. `.leo/rules/SESSION-ALWAYS.md` fails the build if
# any file outside this one installs an EXIT trap of its own.
LEO_ATEXIT=""
leo_atexit_add() { LEO_ATEXIT="${LEO_ATEXIT}${LEO_ATEXIT:+; }$1"; }

# The handler runs on every exit path there is: success, `die`, `set -e`, and
# an interrupt. It must not change the status it was called with and must not
# print, or a failing command starts reporting a different error than the one
# it had.
_leo_atexit() {
  _rc=$?
  set +e
  [ -n "$LEO_ATEXIT" ] && eval "$LEO_ATEXIT" >/dev/null 2>&1
  session_doc_write >/dev/null 2>&1
  return "$_rc"
}
trap '_leo_atexit' EXIT
# INT and TERM do not run an EXIT trap on their own in every bash, and a
# session that was killed mid-command is exactly the one somebody comes back
# to wondering what state it was in.
trap '_leo_atexit; exit 130' INT
trap '_leo_atexit; exit 143' TERM

# -------------------------------------------------------- session doc ----
# SESSION.md: where this session stands, on disk, in markdown, refreshed on
# the way out of every single leo command whether it succeeded or not.
#
# Why a file and not just `leo session --report`: the report is stdout, and
# stdout dies with the terminal. The one moment this is worth anything is the
# moment after something went wrong -- the session dropped, the check failed,
# the agent stopped mid-task -- and in that moment nobody has the scrollback.
#
# Gitignored, like the plan and the manifest: it is the state of one working
# tree at one moment, and the durable record is the commit message.
SESSION_DOC="${ROOT:-.}/SESSION.md"

# session_doc — the document, on stdout. Every number in it is derived from
# disk at the moment it is called; nothing is stored to make it printable.
session_doc() {
  printf '# Session\n\n'
  printf '_Written by leo on every command, including the ones that fail._\n'
  printf '_Generated — do not edit. `%s`_\n\n' "$(now)"

  printf '| | |\n|---|---|\n'
  _pi=$(plan_id)
  _pn=$(plan_name)
  printf '| Plan | %s |\n' "${_pi:+$_pi — }${_pn:-none yet}"
  printf '| Mode | %s |\n' "$(session_desc 2>/dev/null || true)"
  _st=$(plan_status); printf '| Tasks | %s |\n' "${_st:-none declared}"
  _ct=$(task_current)
  if [ -n "$_ct" ]; then
    _td=$(task_todo "$_ct")
    printf '| In flight | %s%s |\n' "$_ct" "${_td:+  ($_td done)}"
  fi
  _l=$(plan_later); [ -n "$_l" ] && printf '| Later | %s |\n' "$_l"
  printf '| Change size | %s file(s), %s line(s) |\n' \
    "$(changed HEAD | wc -l | tr -d ' ')" "$(lines_changed HEAD)"
  if [ -f "$MANIFEST" ]; then
    printf '| Manifest | %s |\n' "$(awk -F'|' '
      /^\| *[0-9NEW]/ { n++; t = $5; gsub(/[ \t]/, "", t); if (t == "") b++ }
      END { printf "%d hunk(s), %d still unreviewed", n + 0, b + 0 }' "$MANIFEST")"
  else
    printf '| Manifest | none |\n'
  fi
  printf '| Recorded, unlanded | %s cycle(s) |\n' "$(record_count)"
  printf '| Next | %s |\n' "$(next_step)"

  # The tools, because "which tools is this agent allowed to use" is the
  # question that is most expensive to get wrong and least visible after the
  # fact.
  if [ -n "${MODE:-}" ]; then
    printf '\n## Tools\n\n| Tool | State | Installed | Used this cycle |\n'
    printf '|---|---|---|---|\n'
    for _c in $CAPS; do
      _rc=0; cap_present "$_c" >/dev/null 2>&1 || _rc=$?
      case "$_rc" in 0) _in=yes ;; 1) _in=NO ;; *) _in='no adapter' ;; esac
      used_has "$_c" && _u=yes || _u=no
      printf '| %s | %s | %s | %s |\n' \
        "$(cap_label "$_c")" "$(cap_state "$_c")" "$_in" "$_u"
    done
  fi

  # Deferred work, spelled out with its reason. A one-word "later" in a table
  # cell is a decision; the reason is the only thing that makes it reviewable.
  if [ -n "$(plan_later)" ]; then
    printf '\n## Later work\n\n'
    # _sd_id, not _t. This loop runs in the calling shell, and the caller is
    # session_doc_write, which is holding the path of the temp file it is
    # about to move into place. A loop variable named _t overwrote it with a
    # task id, `mv` then tried to move the document to a file called "T2", and
    # SESSION.md silently stopped being updated from the moment anything was
    # deferred -- which is precisely the state it exists to report.
    for _sd_id in $(plan_later); do
      _sd_why=$(plan_later_why "$_sd_id")
      printf -- '- **%s** %s — %s\n' \
        "$_sd_id" "$(plan_task_name "$_sd_id")" "${_sd_why:-no reason recorded}"
    done
  fi

  printf '\n## Where the rest of it is\n\n'
  printf -- '- `AGENTS.md` — how to work here, and the tools this session enabled\n'
  printf -- '- `ARCHITECTURE.md` — what the system is\n'
  printf -- '- `CODE_REVIEW.md` — what cycle two argues against\n'
  printf -- '- `RULES.md` — the rules `leo check` enforces\n'
  printf -- '- `.leo/workflow.md` — the loop, in full\n'
}

# session_doc_write — write it, atomically, and never fail.
#
# Called from the exit trap, so every possible failure here is a failure to
# report a failure. It writes to a temp file and moves it into place: a leo
# that is killed halfway through this must leave the previous document intact
# rather than a truncated one, because a truncated status file is worse than a
# stale one -- it looks current.
# _leo_sess_tmp, and not a short name. This function holds a path across a
# call to session_doc, and session_doc calls a dozen helpers that each set
# their own working variables in this same flat namespace. A one- or
# two-letter name here is not a style question: it is a collision waiting for
# whichever helper grows a loop next, and the symptom is a status file that
# stops updating without anything failing.
session_doc_write() {
  [ -n "$ROOT" ] || return 0
  [ -d "$LEO_DIR" ] || return 0
  _leo_sess_tmp=$(mktemp "${TMPDIR:-/tmp}/leo-sess.XXXXXX" 2>/dev/null) || return 0
  if session_doc > "$_leo_sess_tmp" 2>/dev/null && [ -s "$_leo_sess_tmp" ]; then
    # 0644, because mktemp makes it 0600 and mv carries that across. A status
    # file nobody else on the machine can read is a surprise in a shared
    # checkout, and there is nothing private in it that is not already in the
    # repository.
    chmod 644 "$_leo_sess_tmp" 2>/dev/null || true
    mv "$_leo_sess_tmp" "$SESSION_DOC" 2>/dev/null || rm -f "$_leo_sess_tmp"
  else
    rm -f "$_leo_sess_tmp"
  fi
  return 0
}
