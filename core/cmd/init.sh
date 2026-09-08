#!/usr/bin/env bash
# desc: set up a repository for leo
# usage: leo init [--force]
#
# Installs, and never overwrites without --force:
#   AGENTS.md          short, loaded every session, read by every agent
#   CLAUDE.md          one-line bridge to AGENTS.md
#   .leo/workflow.md   the loop the agent follows, read on demand
#   .leo/tasks/        one file per plan task, written by `leo task`
#   .leo/tools/        one per capability: how to use it, what it needs
#   .leo/config        TEST_CMD and friends
#   .leo/rules/        one file per lesson learned, enforced by `leo check`

need_repo
cd "$ROOT"

_force=0
[ "${1:-}" = "--force" ] && _force=1

put() { # put <template> <destination>
  if [ -e "$2" ] && [ "$_force" -eq 0 ]; then
    dim "  skip    $2 (exists)"
  else
    mkdir -p "$(dirname "$2")"
    tmpl_cat "$1" > "$2"
    info "  install $2"
  fi
}

mkdir -p .leo/rules .leo/integrations .leo/tasks .leo/tools .leo/skills

put AGENTS.md      AGENTS.md
put CLAUDE.md      CLAUDE.md
# What this repository is, as opposed to how to work in it. AGENTS.md loads on
# every request and has to stay short enough that a weak model reads to the
# end; everything repo-specific goes here instead.
put CONTEXT.md     CONTEXT.md
put workflow.md    .leo/workflow.md
put rule.md        .leo/rules/EXAMPLE.md
# A README rather than a sample adapter: leo sources every *.sh in that
# directory, so a template that shipped as one would load itself and show up
# as a capability nobody asked for.
put integration.md .leo/integrations/README.md

# One per capability leo ships with. These are what the agent reads before
# using a tool, and they are installed rather than read from $LEO_HOME so a
# team can amend their own copy -- the same reason .leo/workflow.md is a copy.
# Driven off BUILTIN_CAPS so adding a capability cannot forget its doc.
for _cap in $BUILTIN_CAPS; do
  tmpl_has "tools/$_cap.md" || continue
  put "tools/$_cap.md" ".leo/tools/$_cap.md"
done

# The grill is stage one of the loop, and it is somebody else's work: these
# are copied in unmodified so the definition of a grill cannot change under a
# repository between two sessions. See .leo/skills/README.md.
for _s in skills/grilling/SKILL.md skills/grill-me/SKILL.md \
          skills/LICENSE skills/README.md; do
  tmpl_has "$_s" || continue
  put "$_s" ".leo/$_s"
done

if [ ! -f .leo/config ] || [ "$_force" -eq 1 ]; then
  cat > .leo/config <<'CONF'
# leo config — plain shell, committed with the repo.

# How `leo check` verifies the change. Without this, leo can check that the
# work was scoped honestly but not that it works.
TEST_CMD=""
# TEST_CMD="go test ./..."
# TEST_CMD="npm test"
# TEST_CMD="pytest -q"
CONF
  info "  install .leo/config"
fi

# The plan, the manifest and the session are working state; they end up in
# commit messages, so they should not also be tracked as files.
for _ignore in ".leo/plan.md" ".leo/manifest.md" ".leo/session" ".leo/tasks/"; do
  grep -qxF "$_ignore" .gitignore 2>/dev/null || {
    printf '%s\n' "$_ignore" >> .gitignore
    info "  update  .gitignore ($_ignore)"
  }
done

echo >&2
ok "ready"
dim "  1. fill in AGENTS.md — delete every placeholder you do not need"
dim "  2. set TEST_CMD in .leo/config"
dim "  3. start a change: leo plan \"<name>\""
