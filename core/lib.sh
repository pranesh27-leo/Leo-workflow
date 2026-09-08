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

# changed <base> — every file that differs from <base>, plus untracked ones.
changed() {
  { git diff --name-only "${1:-HEAD}" 2>/dev/null
    untracked
  } | sed '/^$/d' | sort -u
}

# is_text <file> — false for binaries, so build output never gets line-counted.
# grep -I reports no match for a binary file on both GNU and BSD.
is_text() { grep -Iq . "$1" 2>/dev/null; }

# lines_changed <base> — added + removed across tracked and untracked files.
# git reports binary diffs as "-", which the awk drops; untracked binaries are
# dropped by is_text before they ever reach it.
lines_changed() {
  { git diff --numstat "${1:-HEAD}" 2>/dev/null
    untracked | while IFS= read -r f; do
        # `is_text && printf` would be wrong here. A binary or empty file makes
        # is_text the last command in the loop body, the loop returns 1, and
        # under `pipefail` the whole substitution fails -- so `set -e` kills the
        # caller on the assignment, after the correct number was computed. An
        # untracked .pyc, a .DS_Store or an empty __init__.py was enough to make
        # `leo check` print the "budget" header and exit with nothing else.
        if is_text "$f"; then
          printf '%s\t0\t%s\n' "$(wc -l <"$f" 2>/dev/null || echo 0)" "$f"
        fi
      done
  } | awk '$1 != "-" { n += $1 + $2 } END { print n + 0 }'
}


now() { date -u '+%Y-%m-%d %H:%M UTC'; }

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
PLAN="$LEO_DIR/plan.md"
MANIFEST="$LEO_DIR/manifest.md"
RULES="$LEO_DIR/rules"

# .leo/config is plain `KEY=value` shell so it needs no parser.
TEST_CMD=""
# shellcheck disable=SC1090
[ -f "$LEO_DIR/config" ] && . "$LEO_DIR/config"

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
      else if (st == "in-progress") { doing = doing (doing ? "," : "") id }
      else if (next_ == "") { next_ = id }
    }
    END {
      if (!total) exit
      printf "%d of %d done", done + 0, total
      if (doing != "") printf "  |  in progress: %s", doing
      else if (next_ != "") printf "  |  next: %s", next_
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
TASKS="$LEO_DIR/tasks"

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
      if (st == "in-progress" && doing == "") doing = id
      if (st != "done" && first == "") first = id
    }
    END { if (doing != "") print doing; else if (first != "") print first }' "$PLAN"
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

  printf 'leo check, then leo commit "<subject>" — the commit is yours'
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

# ------------------------------------------------------------ session ----
# .leo/session declares what kind of work this change is, and which agent
# capabilities that kind of work wants. Plain `KEY=value` shell, like
# .leo/config, so it needs no parser.
#
# It is a declaration, not a switch. leo installs, launches and configures
# nothing; it records what was mediating the agent's view of the code, and that
# ends up in the commit message. Nothing in `leo check` reads it.
#
# Engineering controls are deliberately absent. Plan, task IDs, manifest,
# rules, tests and human commit live in the code that runs them, so there is no
# key here that could turn one off.
SESSION="$LEO_DIR/session"

# The capabilities leo ships with, in display order. Extensions are appended to
# this by cap_discover below; nothing here is positional any more.
BUILTIN_CAPS="serena graph rtk headroom ponytail caveman tdd"

MODE=""
# shellcheck disable=SC1090
[ -f "$SESSION" ] && . "$SESSION"

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
    # shellcheck disable=SC1090
    . "$_adapter"
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
