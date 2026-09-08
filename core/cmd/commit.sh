#!/usr/bin/env bash
# desc: commit, with the manifest in the commit message
# usage: leo commit "<subject>" [--no-check]
#
# The manifest goes in the message body, not in git notes or a side file, so
# that six months from now `git blame` -> `git show` tells you which task a line
# served and what breaks without it. No tooling, no AI, no lost context.
#
# THIS COMMAND IS FOR HUMANS. It refuses to run without someone at a terminal to
# answer for the change. An agent that just wrote the code is the worst possible
# judge of whether the code is done -- it should print this command and stop.

need_repo

# No TTY means nobody is here to say yes: an agent's shell, a pipe, a CI job.
if [ ! -t 0 ] && [ -z "${LEO_YES:-}" ]; then
  err "leo commit needs a human at a terminal"
  info ""
  info "If you are an agent: do not commit. Show the developer what you would run,"
  info "and stop there. They decide when the change is done."
  info ""
  info "If you are a human whose shell has no tty (a script, CI): LEO_YES=1 leo commit ..."
  exit 2
fi

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
  bash "$LEO_SELF" check || die "checks failed — fix them, or commit --no-check"
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

  # What the agent could see when it wrote this. A change made with the prose
  # and context reducers on carries different risk from one made with full
  # diagnostic output, and six months from now the diff will not say which.
  _sess=$(session_desc)
  [ -n "$_sess" ] && printf 'Session: %s\n' "$_sess"
  printf 'Assisted-by: %s\n' "$(who)"
} > "$_msg"

if [ -z "${LEO_YES:-}" ]; then
  head_ "about to commit"
  info "  $_subject"
  info "  $(changed HEAD | wc -l | tr -d ' ') file(s), $(lines_changed HEAD) lines"
  if [ -f "$MANIFEST" ]; then
    _creep=$(awk -F'|' '/^\| *[0-9NEW]/ { t = $5; gsub(/[ \t]/, "", t); if (t == "-") n++ } END { print n + 0 }' "$MANIFEST")
    [ "$_creep" -gt 0 ] && warn "  $_creep hunk(s) in this commit serve no task"
  fi
  printf 'commit? [y/N] ' >&2
  read -r _answer || _answer=n
  _answer=$(printf '%s' "$_answer" | tr -d '\r')   # ptys and git-bash add one
  case "$_answer" in
    [yY]|[yY][eE][sS]) ;;
    *) info "nothing committed"; exit 0 ;;
  esac
fi

git add -A
git commit -F "$_msg"

rm -f "$MANIFEST"
ok "committed $(git rev-parse --short HEAD)"
dim "  read it back: git show --stat HEAD"

# The cheapest thing leo can tell you. An agent session re-reads its whole
# context on every turn, so cost grows with the square of the turn count:
# halving a session's length costs about a third of its tokens, not half. A
# commit is the natural place to stop, and the task files are what make
# stopping free -- .leo/tasks/ holds the state a new session needs.
#
# leo says this here rather than measuring how long the session has run,
# because it cannot see that without reading one specific agent's transcript
# format. A commit landing is something every agent's leo can observe.
dim "  now start a fresh session — .leo/tasks/ carries the state, and a long"
dim "  session pays for every earlier turn on every later one"
