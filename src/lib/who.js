'use strict';
// Which agent is driving, for the Assisted-by trailer.
//
// Detected from the environment each one sets rather than asked for, because
// the answer has to be right in a commit message written six months before
// anybody reads it, and a flag nobody passes defaults to a lie. LEO_AGENT
// overrides everything: a harness leo has never heard of can still name
// itself.
function who() {
  const e = process.env;
  if (e.LEO_AGENT) return e.LEO_AGENT;
  if (e.CLAUDECODE) return 'Claude Code';
  if (e.CURSOR_TRACE_ID) return 'Cursor';
  if (e.CODEX_HOME) return 'Codex';
  if (e.AIDER_MODEL) return 'Aider';
  return 'unknown';
}

module.exports = { who };
