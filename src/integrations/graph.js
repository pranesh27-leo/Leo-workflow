'use strict';
// Code graph — codebase-memory-mcp. Call graph and architecture queries.
const { onPath } = require('./_which');

exports.label = () => 'Code graph';
exports.present = () => onPath('codebase-memory-mcp');

exports.hint = () => [
  'curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash',
  'the installer registers the MCP server with Claude Code itself',
];

exports.advice = (ctx) => {
  const out = ["CLI only:  codebase-memory-mcp cli <tool> '<json>'  — see the doc above"];
  if (ctx.mode === 'debugging' || ctx.mode === 'review') {
    out.push('trace_path — inbound callers first: who reaches the broken thing');
  } else if (ctx.mode === 'learning' || ctx.mode === 'exploration') {
    out.push('get_architecture for the shape, then trace_path outbound to follow a call');
  } else {
    out.push('detect_changes maps this diff to the symbols it touches — read it before leo scan');
  }
  return out;
};

exports.install = () => [
  'curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash',
];

exports.kind = () => 'invoked';
exports.oneline = () => "CLI only: codebase-memory-mcp cli <tool> '<json>' — the MCP wire errors on every call.";
exports.mcp = () => 'trace_path, detect_changes, get_architecture (CLI, not MCP)';
