#!/usr/bin/env bash
# bench-context.sh — what leo costs you per request, before any work happens.
#
# t/bench-session.sh measures sessions that already happened, so it cannot see
# a change you made this morning. This measures the thing that change acts on:
# the bytes an agent re-reads on every single request, forever.
#
# That is leo's real cost. Reading real transcripts showed leo sessions
# spending 1.76x more *cached* tokens per turn than sessions without it, while
# spending 1.71x fewer fresh ones -- and cache re-reads are ~95% of all volume.
# The always-loaded files are why. See .leo/plans/C5-benchmark/RESULTS.md.
#
# No key, no network, and no estimate of anything a machine can count exactly.
set -u

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Turns per session, from real transcripts rather than guessed: the multiplier
# is what turns "2KB" into a number worth caring about.
TURNS=$(python3 - <<'PY'
import json, glob, os
lengths = []
for f in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
    n = 0
    for line in open(f, errors='replace'):
        try: rec = json.loads(line)
        except Exception: continue
        if (rec.get('message') or {}).get('usage'): n += 1
    if n >= 20: lengths.append(n)
lengths.sort()
print(lengths[len(lengths) // 2] if lengths else 200)
PY
2>/dev/null) || TURNS=200
[ -n "$TURNS" ] || TURNS=200

# bytes <file>... — total size, skipping what is not there.
bytes() {
  _n=0
  for _f in "$@"; do
    [ -f "$_f" ] && _n=$((_n + $(wc -c < "$_f")))
  done
  printf '%s' "$_n"
}
words() {
  _n=0
  for _f in "$@"; do
    [ -f "$_f" ] && _n=$((_n + $(wc -w < "$_f")))
  done
  printf '%s' "$_n"
}
show() { printf '    %-30s %8s b %7s w\n' "$1" "$2" "$3"; }

ALWAYS_B=$(bytes templates/AGENTS.md templates/CLAUDE.md)
ALWAYS_W=$(words templates/AGENTS.md templates/CLAUDE.md)

ONDEMAND="templates/workflow.md templates/CONTEXT.md templates/skills/grilling/SKILL.md"
for _t in templates/tools/*.md; do ONDEMAND="$ONDEMAND $_t"; done
# shellcheck disable=SC2086
DEMAND_B=$(bytes $ONDEMAND)
# shellcheck disable=SC2086
DEMAND_W=$(words $ONDEMAND)

echo "leo's per-request footprint"
echo "  median session length on this machine: $TURNS turns"
echo
echo "  ALWAYS LOADED — re-read on every request"
show "AGENTS.md"  "$(bytes templates/AGENTS.md)"  "$(words templates/AGENTS.md)"
show "CLAUDE.md"  "$(bytes templates/CLAUDE.md)"  "$(words templates/CLAUDE.md)"
show "total"      "$ALWAYS_B"                     "$ALWAYS_W"
echo
echo "  READ ON DEMAND — only when the agent opens it"
show "workflow.md"       "$(bytes templates/workflow.md)" "$(words templates/workflow.md)"
show "CONTEXT.md"        "$(bytes templates/CONTEXT.md)"  "$(words templates/CONTEXT.md)"
show "grilling/SKILL.md" "$(bytes templates/skills/grilling/SKILL.md)" "$(words templates/skills/grilling/SKILL.md)"
show "tools/*.md"        "$(bytes templates/tools/*.md)"  "$(words templates/tools/*.md)"
show "total"             "$DEMAND_B"                      "$DEMAND_W"

echo
echo "  over one $TURNS-turn session:"
printf '    always-loaded, read %s times     %10s b\n' "$TURNS" "$((ALWAYS_B * TURNS))"
printf '    on-demand, if every file read twice %10s b\n' "$((DEMAND_B * 2))"
echo
if [ "$((ALWAYS_B * TURNS))" -gt "$((DEMAND_B * 2))" ]; then
  _x=$(( (ALWAYS_B * TURNS) / (DEMAND_B * 2) ))
  echo "  The always-loaded pair costs ${_x}x more over one session than every"
  echo "  on-demand file in leo put together, read twice each. That is the whole"
  echo "  argument for keeping AGENTS.md short and importing nothing into it."
fi
echo
echo "  Enforced by .leo/rules/ALWAYS-LOADED.md: a byte budget, no imports,"
echo "  and tool docs pointed at rather than printed."
