#!/usr/bin/env bash
# desc: declare what kind of work this is, and what the agent may use for it
# usage: leo session                              show the session
#        leo session --mode <name>                set the mode and its defaults
#        leo session --mode debugging --rtk off   ...and override one capability
#        leo session --clear                      end the session
#
#   coding  debugging  learning  review  exploration
#
# This command declares. It does not install, launch, wrap or configure any of
# the tools it names -- those are the developer's, set up once, outside leo. All
# leo does is say which ones this kind of work wants, and put the answer in the
# commit message, so the record shows what was mediating the agent's view of the
# code when it wrote the change.
#
# Engineering controls are not listed as capabilities on purpose: they are in
# the code that runs them, and no mode can turn one off.

need_repo

_mode=""; _clear=0; _set=0; _report=0
# One per capability, discovered rather than listed: an extension in
# .leo/integrations/ is a capability leo has never heard of, and a hardcoded
# set of these is an unbound variable the first time somebody adds one.
for _c in $CAPS; do eval "_new_$_c=''"; done

while [ $# -gt 0 ]; do
  case "$1" in
    --clear)  _clear=1; shift ;;
    --report) _report=1; shift ;;
    --mode)
      _mode="${2:-}"
      [ -n "$_mode" ] || die "--mode needs a name (try: leo session --mode coding)"
      [ -n "$(mode_policy "$_mode")" ] || die "unknown mode: $_mode  (coding, debugging, learning, review, exploration)"
      _set=1; shift 2 ;;
    --*)
      _cap="${1#--}"
      printf '%s\n' $CAPS | grep -qx "$_cap" || die "unknown option: $1"
      case "${2:-}" in
        on|off) eval "_new_$_cap=\$2" ;;
        *)      die "--$_cap takes on or off" ;;
      esac
      _set=1; shift 2 ;;
    *) die "unexpected argument: $1  (try: leo session --mode coding)" ;;
  esac
done

if [ "$_clear" -eq 1 ]; then
  rm -f "$SESSION"
  ok "session cleared"
  exit 0
fi

if [ "$_set" -eq 1 ]; then
  # A new mode resets the overrides: the mode is a fresh set of defaults, and
  # carrying a hand-set capability across a mode change is how someone ends up
  # debugging with the prose compressor still on. Overrides given on the same
  # command line still apply -- they were asked for with the mode in view.
  if [ -n "$_mode" ]; then
    MODE="$_mode"
    for _c in $CAPS; do
      _u=$(printf '%s' "$_c" | tr 'a-z' 'A-Z'); eval "$_u=''"
    done
  else
    [ -n "$MODE" ] || die "no session yet — start one: leo session --mode coding"
  fi

  for _c in $CAPS; do
    eval "_v=\$_new_$_c"
    [ -n "$_v" ] || continue
    _u=$(printf '%s' "$_c" | tr 'a-z' 'A-Z'); eval "$_u=\$_v"
  done

  mkdir -p "$LEO_DIR"
  {
    echo "# leo session — written by \`leo session\`. Read by \`leo check\`."
    echo
    echo "MODE=$MODE"
    for _c in $CAPS; do
      _o=$(cap_over "$_c")
      [ -n "$_o" ] && printf '%s=%s\n' "$(printf '%s' "$_c" | tr 'a-z' 'A-Z')" "$_o"
    done
  } > "$SESSION"
fi

# --- report ---------------------------------------------------------------
# Where the change stands, from what leo already has: the plan, the session,
# git, the manifest. Nothing new is stored to make this printable.
#
# There is no token or savings figure here, and there will not be one. Every
# tool named above measures a different thing against a different denominator,
# over buffers that overlap; adding them produces a number that is false. leo
# reports which capabilities were declared and leaves it there.
if [ "$_report" -eq 1 ]; then
  need_repo
  head_ "leo session report"

  _row() { printf '  %-13s %s\n' "$1" "$2" >&2; }

  _n=$(plan_name);   [ -n "$_n" ]  && _row "Change" "$_n"
  if [ -n "$MODE" ]; then _row "Mode" "$(session_desc)"
  else                    _row "Mode" "none declared"; fi

  _on=""; _miss=""
  for _c in $CAPS; do
    [ "$(cap_state "$_c")" = "on" ] || continue
    _on="$_on${_on:+, }$_c"
    _rc=0; cap_present "$_c" || _rc=$?
    [ "$_rc" -eq 1 ] && _miss="$_miss${_miss:+, }$_c"
  done
  [ -n "$_on" ]   && _row "Declared" "$_on"
  [ -n "$_miss" ] && _row "Not installed" "$_miss"

  _st=$(plan_status); [ -n "$_st" ] && _row "Tasks" "$_st"
  # The to-do inside the task being worked on. The row above is the plan's
  # view -- how many tasks -- and this one is the task file's; neither
  # restates the other.
  _ct=$(task_current)
  if [ -n "$_ct" ]; then
    _cd=$(task_todo "$_ct")
    [ -n "$_cd" ] && _row "To-do" "$_ct  $_cd done"
  fi
  _row "Change size" "$(changed HEAD | wc -l | tr -d ' ') file(s), $(lines_changed HEAD) lines"

  if [ -f "$MANIFEST" ]; then
    _row "Manifest" "$(awk -F'|' '
      /^\| *[0-9NEW]/ {
        n++; t = $5; gsub(/[ \t]/, "", t)
        if (t == "") blank++; else if (t == "-") free++
      }
      END { printf "%d hunk(s), %d reviewed, %d serving no task", n + 0, n - blank, free + 0 }' "$MANIFEST")"
    _row "Tests" "$(sed -n 's/^Tests: *//p' "$MANIFEST" | head -1)"
  else
    _row "Manifest" "none — run: leo scan"
  fi

  # Cycles finished but not landed. Without this row the report would show a
  # change with no manifest and nothing to approve, which is what a change
  # that has not started looks like -- and after a disconnect that is exactly
  # the wrong thing to believe.
  _rn=$(record_count)
  if [ "$_rn" -gt 0 ]; then
    _row "Recorded" "$_rn cycle(s), none in git — leo commit --list"
    _row "Approval" "PENDING — leo commit lands all $_rn as one, and is yours"
  elif [ -f "$MANIFEST" ]; then
    _row "Approval" "PENDING — leo record ends this cycle, leo commit is yours"
  else
    _row "Approval" "nothing to approve yet"
  fi

  # The reminder. The agent is told the loop in .leo/workflow.md; this is the
  # same answer computed from disk, so it stays right when the chat is gone.
  _row "Next" "$(next_step)"

  echo >&2
  dim "  no token figures here on purpose: the tools above measure different"
  dim "  things over overlapping buffers, and summing them would be fiction."
  exit 0
fi

if [ -z "$MODE" ]; then
  warn "no session — start one: leo session --mode coding"
  dim  "  coding  debugging  learning  review  exploration"
  exit 0
fi

# --- show -----------------------------------------------------------------
# One capability per line: what it is set to, whether that came from the mode
# or from you, and whether leo can do anything about it yet. A capability leo
# cannot act on says so rather than looking enabled.
label() {
  command -v "${1}_label" >/dev/null 2>&1 && { "${1}_label"; return 0; }
  case "$1" in
    serena)   printf 'Serena' ;;      rtk)      printf 'RTK' ;;
    headroom) printf 'Headroom' ;;    ponytail) printf 'Ponytail' ;;
    caveman)  printf 'Caveman' ;;
    *)        printf '%s' "$1" ;;
  esac
}

# The note says one thing only: leo names this capability but has no adapter
# for it. Derived from cap_present rather than written down, because the hand-
# written version went stale the day an adapter was added and then contradicted
# the dependencies block three lines further down.
note() {
  [ "$(cap_state "$1")" = "on" ] || return 0
  _rc=0; cap_present "$1" || _rc=$?
  [ "$_rc" -eq 2 ] || return 0
  printf 'no adapter'
}

head_ "leo session"
info "  Mode: $MODE"

group() {   # group <title> <cap>...
  _title="$1"; shift
  [ $# -gt 0 ] || return 0
  head_ "$_title"
  for _c in "$@"; do
    _s=$(cap_state "$_c" | tr 'a-z' 'A-Z')
    _by=""; [ -n "$(cap_over "$_c")" ] && _by="  (you)"
    _nt=$(note "$_c"); [ -n "$_nt" ] && _nt="  $C_DIM$_nt$C_OFF"
    if [ -n "$_by$_nt" ]; then
      printf '  %-13s %-4s%s%s\n' "$(label "$_c")" "$_s" "$_by" "$_nt" >&2
    else
      printf '  %-13s %s\n' "$(label "$_c")" "$_s" >&2
    fi
  done
}

# Anything CAPS gained that leo does not ship with came from
# .leo/integrations/, and gets its own heading rather than being filed under
# one of leo's two.
_extra=""
for _c in $CAPS; do
  printf '%s\n' $BUILTIN_CAPS | grep -qx "$_c" || _extra="$_extra $_c"
done

group "code intelligence" serena graph
group "efficiency" rtk headroom ponytail caveman
# Its own heading. TDD does not mediate what the agent sees -- it says what
# order the work is done in -- and filing it under efficiency would be a lie
# about what it is.
group "practice" tdd
group "extensions" $_extra

# Which runtime the vendored skills are wired for. leo installs them into
# .claude/skills/ and does not guess at Cursor's or Codex's conventions, so a
# team on something else can see at a glance that this part is not for them.
# Printed rather than inferred: a skill nobody can see is the bug this whole
# section exists because of.
if [ -d "$ROOT/.claude/skills" ]; then
  _sk=""
  for _d in "$ROOT"/.claude/skills/*/; do
    [ -f "$_d/SKILL.md" ] || continue
    _sk="$_sk${_sk:+, }$(basename "$_d")"
  done
  if [ -n "$_sk" ]; then
    head_ "skills"
    printf '  %-13s %s\n' "$_sk" "wired for Claude Code (.claude/skills/)" >&2
  fi
fi

# Always on, in every mode, and not settable from here. That is the point of
# the tool: the capabilities above change what the agent sees, and none of them
# gets to change what leo checks.
head_ "engineering controls"
for _c in Plan "Task IDs" Manifest Rules Tests "Human commit"; do
  printf '  %-13s %sON   always%s\n' "$_c" "$C_DIM" "$C_OFF" >&2
done

# --- conflicts ------------------------------------------------------------
# Between what is declared, not between what is installed: a mode that turns on
# two tools that fight is worth saying so even on a machine with neither. This
# is the only place leo comments on the combination rather than the parts.
if [ "$(cap_state rtk)" = "on" ] && [ "$(cap_state headroom)" = "on" ]; then
  head_ "conflicts"
  info "  RTK and Headroom both reduce what the agent reads."
  dim  "    RTK filters shell output structurally; Headroom compresses the"
  dim  "    context semantically, and sees RTK's output already dense. The"
  dim  "    second pass returns less than the first and adds a failure mode"
  dim  "    the first does not have. Running both is a choice, not a mistake."
  dim  "    The reason to drop one is detail work, which the mode already"
  dim  "    does for you. By hand: leo session --headroom off"
fi

# --- dependencies ---------------------------------------------------------
# Only what is on: a capability you turned off is not a dependency. A missing
# tool is a warning and never an error. leo works with none of these installed,
# and that is the property this whole design exists to protect -- an adapter
# that could break `leo check` would be the wrong shape.
head_ "dependencies"
_missing=0
for _c in $CAPS; do
  [ "$(cap_state "$_c")" = "on" ] || continue
  # `cap_present; _rc=$?` would be wrong: under `set -e` a missing tool is a
  # non-zero return in statement position, and the script dies before $? is
  # read. That is the silent-death failure t/smoke.sh was written to catch.
  _rc=0; cap_present "$_c" || _rc=$?
  case "$_rc" in
    0) _state="installed"  ;;
    1) _state="MISSING"; _missing=$((_missing + 1)) ;;
    *) _state="no adapter" ;;
  esac
  printf '  %-13s %s\n' "$(label "$_c")" "$_state" >&2
  # The instruction file, printed from here rather than by each adapter: one
  # line of code instead of seven copies of it. Shown when the tool is here
  # (you are about to use it) and when it is not (you need to know what it
  # wants before installing it). Guarded on the file: an extension in
  # .leo/integrations/ with no doc must print nothing rather than a path to a
  # file that is not there -- an agent reading a missing file learns nothing
  # and proceeds as though it had been told nothing.
  _doc="$LEO_DIR/tools/$_c.md"
  [ -f "$_doc" ] && [ "$_rc" != 2 ] \
    && printf '      instructions: %s\n' "${_doc#"$ROOT"/}" >&2
  # Installed: what to do with it. Missing: how to get it. Neither, if leo has
  # no adapter -- there is nothing honest to say.
  case "$_rc" in
    0) cap_call "$_c" advice ;;
    1) cap_call "$_c" hint ;;
  esac | sed 's/^/      /' >&2
done

echo >&2
if [ "$_missing" -gt 0 ]; then
  warn "$_missing enabled capability(s) not installed — leo works without them"
  dim  "  install one above, or drop it here: leo session --<name> off"
fi
dim "  leo does not install these. It does check them: a tool that is ON and\n  installed must be announced with leo use, or leo check fails."
