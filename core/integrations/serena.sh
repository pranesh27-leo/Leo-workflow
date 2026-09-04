#!/usr/bin/env bash
# Serena — semantic code intelligence. MIT, github.com/oraios/serena
#
# The code-understanding layer: find a symbol, find what references it, edit it
# by name rather than by line number. leo does not duplicate any of that and
# does not launch it. Serena is an MCP server the developer configures once.

serena_present() { command -v serena >/dev/null 2>&1; }

serena_hint() {
  say "uv tool install -p 3.13 serena-agent"
  say "claude mcp add serena -- serena start-mcp-server --context claude-code --project \"\$(pwd)\""
}

# Serena has its own modes, and they line up with leo's. Saying so is the whole
# integration: leo names the mode, the developer passes it, nothing is wrapped.
serena_advice() {
  case "$MODE" in
    coding|debugging) say "serena --mode editing — symbol lookup and symbolic edits" ;;
    *)                say "serena --mode planning — read and analyse, do not edit" ;;
  esac
  say "find_symbol and find_referencing_symbols before grep"
}

# What `leo install serena` will run. It prints; leo shows it, asks, then runs
# it. The MCP registration is only emitted when the claude CLI is actually
# here, because a line that cannot work should not be in a script someone is
# being asked to approve.
serena_install() {
  say "uv tool install -p 3.13 serena-agent"
  if command -v claude >/dev/null 2>&1; then
    say "claude mcp add serena -- serena start-mcp-server --context claude-code --project '${ROOT:-.}'"
  fi
}
