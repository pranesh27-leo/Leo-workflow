#!/usr/bin/env bash
# desc: record this cycle's commit message without committing
# usage: leo record "<subject>" [--no-check]
#
# The end of a cycle, without the end of the change. leo checks the work, files
# the message this cycle would have committed -- subject, goal, manifest,
# session -- into .leo/commits/, clears the manifest, and stops. Nothing lands.
#
# `leo commit` then folds every record into one commit, when the developer has
# seen the whole change and not before. That is the point: "is this cycle
# finished" and "is this change done" are different questions, and committing
# made you answer the second one every time you meant the first.
#
# Unlike `leo commit`, an agent may run this. It writes no history and touches
# neither the index nor the working tree -- undoing it is deleting one file.

need_repo

_subject=""; _check=1
while [ $# -gt 0 ]; do
  case "$1" in
    --no-check) _check=0; shift ;;
    -*)         die "unknown option: $1" ;;
    *)          _subject="${_subject:+$_subject }$1"; shift ;;
  esac
done
[ -n "$_subject" ] || die 'usage: leo record "<subject>"'

# The same gate the commit used to carry. A record that was never checked is a
# record that will be checked at landing time instead, in a batch, against a
# manifest that has already been consumed -- which is to say never.
if [ "$_check" -eq 1 ]; then
  bash "$LEO_SELF" check || die "checks failed — fix them, or record --no-check"
fi

_base=$(record_base)
if [ -z "$(changed "$_base")" ]; then
  die "nothing has changed since the last record — nothing to record"
fi

mkdir -p "$RECORDS"
_id=$(record_next_id)
_file="$RECORDS/$_id.md"

# The tree this cycle leaves behind, so the next `leo scan` enumerates only the
# next cycle's hunks. It touches neither the index nor git history -- see
# base_index for why that matters. Taken before the file is written: .leo/commits/ is
# gitignored, so the record cannot appear in its own snapshot either way, but
# the ordering is what makes that true rather than incidental.
_tree=$(snapshot_tree)

{
  printf 'Subject: %s\n' "$_subject"
  printf 'Date: %s\n' "$(date -u '+%Y-%m-%d %H:%M UTC')"
  printf 'Tree: %s\n' "$_tree"
  _sess=$(session_desc)
  [ -n "$_sess" ] && printf 'Session: %s\n' "$_sess"
  printf 'Assisted-by: %s\n' "$(who)"
  printf '\n'

  # The plan's goal, so the record states intent before it states mechanics.
  if [ -f "$PLAN" ]; then
    _goal=$(awk '
      /^## Goal/ { g = 1; next }
      g && /^##/ { exit }
      g && NF && $0 !~ /^</ { print; exit }' "$PLAN")
    [ -n "$_goal" ] && printf 'Goal: %s\n\n' "$_goal"
  fi

  # Which declared tools actually built these hunks. It sits next to the
  # manifest for the same reason the manifest sits in the commit message: the
  # answer is only meaningful beside the code it is an answer about.
  _tools=$(used_list | tr '\n' ' ' | sed 's/ *$//')
  [ -n "$_tools" ] && printf 'Tools: %s\n\n' "$_tools"

  if [ -f "$MANIFEST" ]; then
    # The scan writes a "Base:" line whenever it did not diff against HEAD, and
    # for a second cycle that base is the previous record's tree. A tree sha is
    # worth nothing to whoever reads this commit years from now -- the object
    # is unreachable and will have been collected -- so it is dropped here
    # while a real one (`leo scan main`) is kept.
    sed '1{/^# Manifest$/d;}' "$MANIFEST" \
      | sed "/^Base: *$_base\$/d" \
      | sed '/./,$!d'
  else
    warn "no manifest — this record says what changed but not why"
  fi
} > "$_file"

# The manifest is spent: it is inside the record now, and leaving it would make
# the next `leo scan` refuse to start. The tool ledger goes with it -- it
# answers "what built these hunks", and the next cycle's hunks are different
# hunks.
rm -f "$MANIFEST" "$USED"

_n=$(record_count)
ok "recorded $_id — nothing committed"
dim "  $_subject"
dim "  ${_file#"$ROOT"/}"
info ""
info "$_n cycle(s) recorded. Nothing is in git yet."
dim  "  read them back: leo commit --list"
dim  "  land them all:  leo commit          <- the developer's, and one commit"

# Same reasoning as the commit used to carry: a session re-reads its whole
# context every turn, so cost grows with the square of the turn count. A
# finished cycle is the natural place to stop whether or not it landed, and
# .leo/tasks/ plus .leo/commits/ hold everything a new session needs.
info ""
dim "  now start a fresh session — .leo/tasks/ and .leo/commits/ carry the"
dim "  state, and a long session pays for every earlier turn on every later one"
