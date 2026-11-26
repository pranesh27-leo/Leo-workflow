#!/usr/bin/env node
'use strict';
// The reading budget. Claude Code and Codex both run this when a reply is
// about to finish (the Stop hook).
//
// An agent can write 400 lines in one reply. A developer cannot read 400
// lines before typing the next prompt, so they type it without reading, and
// by the next reply the code is something nobody understood. The fix is not
// to read faster. It is to keep one reply small enough to read, and when a
// reply is not, to make the agent hand over a map before it goes on.
//
// trace.js counts the lines each tool call adds and removes. This reads that
// count against `Lines:` in AGENTS.md. Over it, the reply is sent back once
// with one job: write no more code, and give the developer a reading guide,
// riskiest change first, each with where its shape came from.
//
// It blocks once per reply and then resets, so it cannot loop. Node and the
// standard library only.

const fs = require('fs');
const path = require('path');
const { state } = require('./trace.js');

const DEFAULT = 150;

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch (e) { return ''; }
}

function rootOf(dir) {
  let d = dir;
  for (;;) {
    if (fs.existsSync(path.join(d, '.git'))) return d;
    const up = path.dirname(d);
    if (up === d) return dir;
    d = up;
  }
}

// `Lines: 150` in the session block. The developer's number, not ours.
function cap(root) {
  try {
    const m = /^\s*Lines:\s*(\d+)/m.exec(fs.readFileSync(path.join(root, 'AGENTS.md'), 'utf8'));
    if (m) return +m[1];
  } catch (e) { /* no AGENTS.md: use the default */ }
  return DEFAULT;
}

function main() {
  let input;
  try { input = JSON.parse(readStdin() || '{}'); } catch (e) { return 0; }
  const s = state(input.session_id || 'none');
  let t;
  try { t = JSON.parse(fs.readFileSync(s, 'utf8')); } catch (e) { return 0; }
  // Every stop resets the count: the budget is per reply.
  try { fs.unlinkSync(s); } catch (e) { /* gone */ }

  const max = cap(rootOf(input.cwd || process.cwd()));
  if (!t || t.lines <= max || input.stop_hook_active) return 0;

  const files = Object.entries(t.files).sort((a, b) => b[1] - a[1]);
  const list = files.slice(0, 5).map(([f, n]) => f + ' ' + n).join(', ') + (files.length > 5 ? ', …' : '');
  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason: 'budget: this reply changed ' + t.lines + ' lines (' + list + '). The developer reads about ' + max +
      ' per reply (`Lines:` in AGENTS.md), so they cannot follow this before the next prompt.\n' +
      'Write no more code in this reply. Send a reading guide instead: the changes in reading order, riskiest first, one row each:\n' +
      '  `path:LINE` — what it does — Source: grill | pattern `path:LINE` | default\n' +
      'Mark every `default`: a choice nobody asked for and no code here showed you. Those are the rows to read closely.\n' +
      'Next time, split the task so one reply stays under ' + max + ' lines (.agents/leo.md, stage 8).',
  }) + '\n');
  return 0;
}

process.exitCode = main();
