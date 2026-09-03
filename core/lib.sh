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
        is_text "$f" && printf '%s\t0\t%s\n' "$(wc -l <"$f" 2>/dev/null || echo 0)" "$f"
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
