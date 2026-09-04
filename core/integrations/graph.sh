#!/usr/bin/env bash
# Code graph — call chains and blast radius.
# MIT, github.com/DeusData/codebase-memory-mcp
#
# The relationship layer, and the one that is genuinely complementary rather
# than overlapping. Serena answers "where is this symbol and who references
# it". A graph answers "what breaks if I change it" -- callers of callers,
# routes, the subsystem a file belongs to.
#
# `detect_changes` is the tool worth knowing about here: it maps a git diff to
# the symbols it affects, which is the same question `leo scan` asks of a diff
# from the other direction. A manifest row's "If deleted" column is exactly
# where that answer belongs.
#
# leo shipped without a graph adapter for one release because the best-known
# tool for this, GitNexus, is PolyForm Noncommercial -- and most people reading
# this write code at work. This one is MIT and a single static binary with no
# runtime of its own, which is the only reason it is here.

graph_present() { command -v codebase-memory-mcp >/dev/null 2>&1; }

graph_label() { printf 'Code graph'; }

graph_hint() {
  say "curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash"
  say "the installer registers the MCP server with Claude Code itself"
}

graph_install() {
  say "curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash"
}

graph_advice() {
  # The headline, before anything about which query to run: the MCP wire
  # returns "Cannot read properties of undefined" on every call, and the CLI
  # returns the same data. An agent that only knows the MCP names concludes
  # the tool is dead and stops using it.
  say "CLI only:  codebase-memory-mcp cli <tool> '<json>'  — see the doc above"
  case "$MODE" in
    debugging|review)
      say "trace_path — inbound callers first: who reaches the broken thing" ;;
    learning|exploration)
      say "get_architecture for the shape, then trace_path outbound to follow a call" ;;
    *)
      say "detect_changes maps this diff to the symbols it touches — read it before leo scan" ;;
  esac
}
