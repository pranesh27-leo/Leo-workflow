#!/usr/bin/env bash
# desc: commit, with the manifest in the commit message
# usage: leo commit "<subject>" [--no-check]
#
# The manifest goes in the message body, not in git notes or a side file, so
# that six months from now `git blame` -> `git show` tells you which task a line
# served and what breaks without it. No tooling, no AI, no lost context.

need_repo

_subject=""; _check=1
while [ $# -gt 0 ]; do
  case "$1" in
    --no-check) _check=0; shift ;;
    -*)         die "unknown option: $1" ;;
    *)          _subject="${_subject:+$_subject }$1"; shift ;;
  esac
done
[ -n "$_subject" ] || die 'usage: leo commit "<subject>"'

if [ "$_check" -eq 1 ]; then
  bash "$LEO_HOME/bin/leo" check || die "checks failed — fix them, or commit --no-check"
fi

_msg=$(mktemp "${TMPDIR:-/tmp}/leo-msg.XXXXXX")
trap 'rm -f "$_msg"' EXIT

{
  printf '%s\n\n' "$_subject"

  # The plan's goal, so the commit states intent before it states mechanics.
  if [ -f "$PLAN" ]; then
    _goal=$(awk '
      /^## Goal/ { g = 1; next }
      g && /^##/ { exit }
      g && NF && $0 !~ /^</ { print; exit }' "$PLAN")
    [ -n "$_goal" ] && printf 'Goal: %s\n\n' "$_goal"
  fi

  if [ -f "$MANIFEST" ]; then
    sed '1{/^# Manifest$/d;}' "$MANIFEST" | sed '/./,$!d'
    printf '\n'
  else
    warn "no manifest — this commit records what changed but not why"
  fi

  printf 'Assisted-by: %s\n' "$(who)"
} > "$_msg"

git add -A
git commit -F "$_msg"

rm -f "$MANIFEST"
ok "committed $(git rev-parse --short HEAD)"
dim "  read it back: git show --stat HEAD"
