#!/usr/bin/env bash
# desc: set up a repository for leo
# usage: leo init [--force]
#
# Installs, and never overwrites without --force:
#   AGENTS.md          short, loaded every session, read by every agent
#   CLAUDE.md          one-line bridge to AGENTS.md
#   .leo/workflow.md   the loop the agent follows, read on demand
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
    cp "$LEO_HOME/templates/$1" "$2"
    info "  install $2"
  fi
}

mkdir -p .leo/rules

put AGENTS.md   AGENTS.md
put CLAUDE.md   CLAUDE.md
put workflow.md .leo/workflow.md
put rule.md     .leo/rules/EXAMPLE.md

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

# The plan and the manifest are working state; they end up in commit messages,
# so they should not also be tracked as files.
for _ignore in ".leo/plan.md" ".leo/manifest.md"; do
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
