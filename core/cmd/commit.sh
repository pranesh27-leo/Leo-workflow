#!/usr/bin/env bash
# desc: land every recorded cycle as one commit
# usage: leo commit ["<subject>"] [--no-check] [--list]
#
# The manifest goes in the message body, not in git notes or a side file, so
# that six months from now `git blame` -> `git show` tells you which task a line
# served and what breaks without it. No tooling, no AI, no lost context.
#
# Two shapes, and which one runs depends on whether any cycle has been recorded:
#
#   records waiting   every record becomes a section of one commit message, in
#                     the order the cycles happened. This is the normal shape:
#                     cycles end with `leo record`, and the change lands once,
#                     when the developer has seen all of it.
#   no records        the manifest goes straight into a commit, as it did
#                     before records existed. A one-cycle change never needs a
#                     record, and this is the same command it always was.
#
# THIS COMMAND IS FOR HUMANS. It refuses to run without someone at a terminal to
# answer for the change. An agent that just wrote the code is the worst possible
# judge of whether the code is done -- it should run `leo record` and stop.

need_repo

_subject=""; _check=1; _list=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-check) _check=0; shift ;;
    --list)     _list=1; shift ;;
    -*)         die "unknown option: $1" ;;
    *)          _subject="${_subject:+$_subject }$1"; shift ;;
  esac
done

_n=$(record_count)

if [ "$_list" -eq 1 ]; then
  [ "$_n" -gt 0 ] || { info "no cycles recorded — the next commit is a plain one"; exit 0; }
  head_ "$_n cycle(s) recorded, none of them in git"
  records | while IFS= read -r _r; do
    info "  $(basename "$_r" .md)  $(record_field "$_r" Subject)"
    dim  "      $(record_field "$_r" Date)"
  done
  info ""
  dim "  land them: leo commit \"<subject>\""
  exit 0
fi

# No TTY means nobody is here to say yes: an agent's shell, a pipe, a CI job.
# After --list, which reads and changes nothing -- an agent showing the
# developer what is waiting to land is exactly the behaviour this gate wants.
if [ ! -t 0 ] && [ -z "${LEO_YES:-}" ]; then
  err "leo commit needs a human at a terminal"
  info ""
  info "If you are an agent: do not commit. Record the cycle instead --"
  info "leo record \"<subject>\" -- and show them: leo commit"
  info ""
  info "If you are a human whose shell has no tty (a script, CI): LEO_YES=1 leo commit ..."
  exit 2
fi

# A subject is required when nothing is recorded, because there is nothing else
# to write one from. With one record its subject is the obvious default, and
# with several the developer is asked -- that is the whole reason records
# exist, so the subject is written once, over the finished change.
if [ -z "$_subject" ] && [ "$_n" -eq 0 ]; then
  die 'usage: leo commit "<subject>"    (or: leo record "<subject>" to defer it)'
fi
if [ -z "$_subject" ] && [ "$_n" -eq 1 ]; then
  _subject=$(record_field "$(records)" Subject)
fi
if [ -z "$_subject" ]; then
  [ -z "${LEO_YES:-}" ] || die "$_n records — pass the subject: leo commit \"<subject>\""
  head_ "$_n cycle(s) recorded"
  records | while IFS= read -r _r; do
    info "  $(record_field "$_r" Subject)"
  done
  info ""
  info "One subject for all of it:"
  printf '> ' >&2
  read -r _subject || _subject=""
  _subject=$(printf '%s' "$_subject" | tr -d '\r')
  [ -n "$_subject" ] || die "no subject — nothing committed"
fi

if [ "$_check" -eq 1 ]; then
  bash "$LEO_SELF" check || die "checks failed — fix them, or commit --no-check"
fi

_msg=$(mktemp "${TMPDIR:-/tmp}/leo-msg.XXXXXX")
trap 'rm -f "$_msg"' EXIT

{
  printf '%s\n\n' "$_subject"

  # Each recorded cycle keeps its own section: its subject, when it was
  # recorded, what it could see, and its own manifest. Merging the tables into
  # one would be shorter and would lose the only thing worth having -- which
  # hunks were reviewed together, against which goal.
  records | while IFS= read -r _r; do
    printf -- '--- %s: %s\n' "$(basename "$_r" .md)" "$(record_field "$_r" Subject)"
    _rs=$(record_field "$_r" Session)
    [ -n "$_rs" ] && printf 'Session: %s\n' "$_rs"
    printf 'Recorded: %s\n\n' "$(record_field "$_r" Date)"
    # Everything after the header block: the goal and the manifest table.
    sed '1,/^$/d' "$_r"
    printf '\n'
  done

  # The plan's goal, so the commit states intent before it states mechanics.
  # Records carry their own, so this is for the un-recorded remainder.
  if [ "$_n" -eq 0 ] && [ -f "$PLAN" ]; then
    _goal=$(awk '
      /^## Goal/ { g = 1; next }
      g && /^##/ { exit }
      g && NF && $0 !~ /^</ { print; exit }' "$PLAN")
    [ -n "$_goal" ] && printf 'Goal: %s\n\n' "$_goal"
  fi

  if [ -f "$MANIFEST" ]; then
    sed '1{/^# Manifest$/d;}' "$MANIFEST" | sed '/./,$!d'
    printf '\n'
  elif [ "$_n" -eq 0 ]; then
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
  [ "$_n" -gt 0 ] && info "  $_n recorded cycle(s), landing as one commit"
  # Work done after the last record belongs to no cycle: it was never scanned,
  # never manifested, and it is about to be committed alongside work that was.
  if [ "$_n" -gt 0 ] && [ ! -f "$MANIFEST" ]; then
    _loose=$(changed "$(record_base)" | wc -l | tr -d ' ')
    [ "$_loose" -gt 0 ] && warn "  $_loose file(s) changed since the last record, in no manifest"
  fi
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
# The records are spent: every one of them is inside the commit message now,
# which is the only place they were ever going.
rm -rf "$RECORDS"
ok "committed $(git rev-parse --short HEAD)"
[ "$_n" -gt 0 ] && dim "  $_n recorded cycle(s) landed as one commit"
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

# --- cycle two ------------------------------------------------------------
# The commit ends the dev cycle; it does not end the work. The change now
# exists and nothing has read it except the developer who wrote it, which is
# the one reviewer whose opinion is already spent.
#
# leo asks here rather than starting it, for the same reason it does not
# commit: a review is a session's worth of work, and scheduling it is the
# developer's call. What it can do is make the ask unmissable and hand over the
# exact command, at the one moment the change is fresh in everyone's mind.
#
# The fresh session above and the review are the same session. That is not a
# coincidence -- cycle two needs almost nothing this session is carrying, and
# everything it does need is in the commit message that was just written.
info ""
head_ "review it?"
info "  The change is in, and unreviewed. Cycle two is a separate flow: it"
info "  reads this commit -- goal, manifest and session are all in the message"
info "  -- and it cannot edit the code, only find things about it."
info ""
dim  "  leo session --mode review"
dim  "  leo review $(git rev-parse --short HEAD)"
info ""
dim  "  It ends at: leo review --close"
