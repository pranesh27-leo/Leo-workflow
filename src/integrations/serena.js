'use strict';
// Serena — semantic code intelligence. MIT, github.com/oraios/serena
//
// The code-understanding layer: find a symbol, find what references it, edit
// it by name rather than by line number. leo does not duplicate any of that
// and does not launch it. Serena is an MCP server the developer configures
// once.
const { onPath } = require('./_which');

exports.label = () => 'Serena';
exports.present = () => onPath('serena');

exports.hint = () => [
  'uv tool install -p 3.13 serena-agent',
  'claude mcp add serena -- serena start-mcp-server --context claude-code --project "$(pwd)"',
];

// Serena has its own modes, and they line up with leo's. Saying so is the
// whole integration: leo names the mode, the developer passes it, nothing is
// wrapped.
exports.advice = (ctx) => {
  const m = ctx.mode;
  const first = (m === 'coding' || m === 'debugging')
    ? 'serena --mode editing — symbol lookup and symbolic edits'
    : 'serena --mode planning — read and analyse, do not edit';
  return [first, 'find_symbol and find_referencing_symbols before grep'];
};

// What `leo install serena` will run. It prints; leo shows it, asks, then
// runs it. The MCP registration is only emitted when the claude CLI is
// actually here, because a line that cannot work should not be in a script
// someone is being asked to approve.
exports.install = (ctx) => {
  const out = ['uv tool install -p 3.13 serena-agent'];
  if (onPath('claude')) {
    out.push("claude mcp add serena -- serena start-mcp-server --context claude-code --project '" + (ctx.root || '.') + "'");
  }
  return out;
};

// Invoked: the agent calls this at a moment, so the mark it leaves is the
// agent saying so -- `leo use serena`.
exports.kind = () => 'invoked';
exports.oneline = () => 'find_symbol / find_referencing_symbols before grep — grep cannot answer "who calls this".';
exports.mcp = () => 'find_symbol, find_referencing_symbols, replace_symbol_body';
