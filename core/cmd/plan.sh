#!/usr/bin/env bash
# desc: write or show the plan — what this change is allowed to be
# usage: leo plan                    show the current plan
#        leo plan "<name>" [--force] start a new plan
#
# The plan is the yardstick. Without one, "did the AI do what I asked?" has no
# answer, and `leo check` has no budget to measure against.

need_repo

_name=""; _force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) _force=1; shift ;;
    *)       _name="$1"; shift ;;
  esac
done

if [ -z "$_name" ]; then
  [ -f "$PLAN" ] || { warn "no plan yet — start one: leo plan \"<name>\""; exit 0; }
  cat "$PLAN"
  exit 0
fi

if [ -f "$PLAN" ] && [ "$_force" -eq 0 ]; then
  die "$PLAN already exists (use --force to replace it)"
fi

mkdir -p "$LEO_DIR"
cat > "$PLAN" <<PLANEOF
# Plan: $_name

Created: $(now)

## Goal
<One sentence: what changes, and why.>

## Non-goals
<What this change explicitly does not touch. This is what stops scope creep.>

## Wrong-change signal
<The one observation that would mean this is the wrong change entirely.>

## Tasks

| #  | Task          | Files   | Est LOC | Status  |
|----|---------------|---------|---------|---------|
| T1 | <first task>  | <files> | <n>     | pending |
| T2 | <second task> | <files> | <n>     | pending |

Status: pending -> in-progress -> done.
Task IDs must be T1, T2, ... — leo and the manifest match on that format.

## Budget
est: <n> LOC
PLANEOF

ok "plan created: .leo/plan.md"
dim "  Fill it in, then have the agent work one task at a time."
