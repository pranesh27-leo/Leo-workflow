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

# plan_name — the change this plan is for, from its title line.
plan_name() {
  [ -f "$PLAN" ] || return 0
  sed -n 's/^# Plan: *//p' "$PLAN" | head -1
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

# The capabilities leo knows how to declare, in display order. The order is the
# contract: mode_policy returns one value per name, positionally.
CAPS="serena graph rtk headroom ponytail caveman"

MODE=""
SERENA=""; GRAPH=""; RTK=""; HEADROOM=""; PONYTAIL=""; CAVEMAN=""
# shellcheck disable=SC1090
[ -f "$SESSION" ] && . "$SESSION"

# mode_policy <mode> — the default state of every capability, in CAPS order.
# Empty for a mode leo does not know, which is how the caller validates one.
#
# Debugging, learning and exploration turn the semantic reducers off: during
# those, the thing that matters is often the thing that looks like noise. RTK
# stays on throughout because its filtering is structural (progress bars,
# repeated lines) rather than a model deciding what you needed to see.
mode_policy() {
  #     serena graph rtk headroom ponytail caveman
  case "$1" in
    coding)      echo "on  off  on  on   on   off" ;;
    debugging)   echo "on  on   on  off  off  off" ;;
    learning)    echo "on  on   on  off  off  off" ;;
    review)      echo "on  on   on  on   off  off" ;;
    exploration) echo "on  on   on  off  off  off" ;;
  esac
}

# cap_over <cap> — the explicit override for a capability, or empty. An
# override is stored uppercased, so `--caveman on` is CAVEMAN=on in the file.
cap_over() {
  _u=$(printf '%s' "$1" | tr 'a-z' 'A-Z')
  printf '%s' "${!_u:-}"
}

# cap_state <cap> — what it is actually set to: the override if there is one,
# otherwise the mode's default. Empty when there is no session at all.
cap_state() {
  [ -n "$MODE" ] || return 0
  _o=$(cap_over "$1")
  [ -n "$_o" ] && { printf '%s' "$_o"; return 0; }
  _i=1
  for _c in $CAPS; do
    [ "$_c" = "$1" ] && break
    _i=$((_i + 1))
  done
  mode_policy "$MODE" | awk -v i="$_i" '{ printf "%s", $i }'
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
for _adapter in "$LEO_HOME/core/integrations"/*.sh; do
  # shellcheck disable=SC1090
  [ -f "$_adapter" ] && . "$_adapter"
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
