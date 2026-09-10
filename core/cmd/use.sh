#!/usr/bin/env bash
# desc: announce a tool you are about to use, and log it
# usage: leo use <name> [--list]
#
# The announcement and the evidence are one action, deliberately. A standing
# order to "tell the developer which tool you are using" is the kind of
# instruction that silently stops happening halfway through a session, and
# nothing would notice. Here the line the developer sees IS the line `leo check`
# reads, so the two can never drift apart.
#
# What it does, in order: refuse if the session says this tool is off, print
# what is being used and where its instructions live, and write one line to
# .leo/used.
#
# It does not launch, wrap or configure the tool. leo has never done that and
# this does not start: `leo use serena` is the agent saying "I am about to use
# serena", not leo running it.

need_repo

_list=0; _cap=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list) _list=1; shift ;;
    -*)     die "unknown option: $1" ;;
    *)      _cap="$1"; shift ;;
  esac
done

if [ "$_list" -eq 1 ]; then
  if [ ! -f "$USED" ]; then
    info "no tool logged this cycle"
    exit 0
  fi
  head_ "used this cycle"
  while IFS="$(printf '\t')" read -r _n _when _note; do
    [ -n "$_n" ] || continue
    if [ "${_note:-}" = "DENIED" ]; then
      err "  $_n  $_when  — refused, and used anyway"
    else
      info "  $_n  $_when"
    fi
  done < "$USED"
  exit 0
fi

[ -n "$_cap" ] || die 'usage: leo use <name>    (leo session shows what is on)'

# A name leo has no adapter for is a typo, or a tool nobody wrote an adapter
# for. Either way it must not be logged: a ledger that accepts anything proves
# nothing, and `leo check` would then read a name it cannot resolve to a switch.
printf '%s\n' $CAPS | grep -qx "$_cap" || {
  err "no such tool: $_cap"
  info ""
  info "leo knows: $(printf '%s' "$CAPS" | tr '\n' ' ')"
  dim  "  add one by dropping an adapter in .leo/integrations/ — see the README there"
  exit 1
}

_state=$(cap_state "$_cap")
_label=$(cap_call "$_cap" label); _label="${_label:-$_cap}"
_doc=".leo/tools/$_cap.md"

# No session at all: nothing is switched on or off, so there is nothing to
# refuse. Log it anyway -- the record of what built these hunks is worth having
# whether or not anyone declared a mode.
if [ -z "$MODE" ]; then
  warn "no session declared — nothing is on or off"
  dim  "  declare one: leo session --mode coding"
  used_log "$_cap"
  ok "using $_label"
  exit 0
fi

# --- the off switch -------------------------------------------------------
# Refusing is prevention; recording the attempt is detection. An agent that
# reads this and stops is the point. An agent that reads it and proceeds has
# left a line in the ledger that `leo check` fails on, which is the next best
# thing.
if [ "$_state" != "on" ]; then
  used_log "$_cap" DENIED
  err "$_label is OFF in this session — do not use it"
  info ""
  info "The mode is the developer's. If this work genuinely needs $_cap, say so"
  info "and show them the command. Do not turn it on yourself."
  info ""
  dim  "  theirs to run:  leo session --$_cap on"
  exit 1
fi

# --- on -------------------------------------------------------------------
# Second and later calls in the same cycle announce without re-logging: the
# developer still sees what is being used, and the ledger stays one line per
# tool. See used_log for why that matters more than it looks.
if used_has "$_cap"; then
  dim "using $_label (already logged this cycle)"
  exit 0
fi

# Declared but not installed is worth saying out loud and is not the agent's
# fault, so it warns rather than refusing. The log still happens: what the
# agent believed it was using is part of the record either way.
_rc=0; cap_present "$_cap" || _rc=$?
case "$_rc" in
  1) warn "$_label is ON but not installed here" 
     dim  "  the developer's call: leo install $_cap" ;;
  2) warn "$_label has no adapter — leo cannot tell whether it is installed" ;;
esac

used_log "$_cap"
ok "using $_label"
# Pointed at, never printed. Seven tool docs inlined would be seven files in
# the context of a session that needed one -- the whole reason they live on
# disk instead of in AGENTS.md.
#
# `[ -f x ] && dim ...` would be the obvious line and would be wrong: it is the
# last command in the file, so a repository with no tool doc makes `leo use`
# exit 1 having done its whole job. The agent then reads a failure where leo
# printed success.
if [ -f "$ROOT/$_doc" ]; then
  dim "  $_doc   <- how it is meant to be used here"
fi
exit 0
