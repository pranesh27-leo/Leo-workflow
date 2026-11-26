#!/usr/bin/env node
'use strict';
// The trace. Claude Code and Codex both run this after every tool call (the
// PostToolUse hook), with the call it made as tool_name and tool_input.
//
// The ▶ / ✓ lines in AGENTS.md are the agent's own account of what it did.
// An account written by the thing being accounted for is a story, and a story
// can leave out the file it read first or the command it ran twice. This
// writes down what actually ran, one row per call, from the runtime's side:
//
//   .agents/goals/G<n>/trace.md    while a goal is open (the highest G<n>)
//   .agents/trace.md               when there is none
//
// It also counts the lines each reply changes, for budget.js, the Stop hook
// that stops one reply writing more than the developer can read.
//
// It never blocks and never fails the call: a trace that breaks the work it
// traces is worse than no trace. Node and the standard library only.

const fs = require('fs');
const os = require('os');
const path = require('path');

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

// The open goal is the highest G<n>: ids never restart (.agents/leo.md), so
// the newest goal is always the largest number.
function traceFile(root) {
  const agents = path.join(root, '.agents');
  if (!fs.existsSync(agents)) return null;
  let best = 0;
  try {
    for (const d of fs.readdirSync(path.join(agents, 'goals'))) {
      const m = /^G(\d+)$/.exec(d);
      if (m && +m[1] > best) best = +m[1];
    }
  } catch (e) { /* no goals yet */ }
  return best ? path.join(agents, 'goals', 'G' + best, 'trace.md') : path.join(agents, 'trace.md');
}

const count = (s) => (typeof s === 'string' && s ? s.split('\n').length - (s.endsWith('\n') ? 1 : 0) : 0);
const cell = (s) => String(s).replace(/\r?\n/g, ' ⏎ ').replace(/\|/g, '\\|');
const clip = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s);

function rel(p, root) {
  if (typeof p !== 'string' || !p) return '';
  const r = path.relative(root, path.resolve(root, p));
  return (r && !r.startsWith('..') ? r : p).replace(/\\/g, '/');
}

// One call, as a row: what it touched, and the lines it added and removed.
// Lines are counted from the call's own input, so an edit made through the
// shell (sed -i, a heredoc) shows as a command with no count. The trace
// says so rather than guessing.
function describe(tool, ti, tr, root) {
  const f = rel(ti.file_path || ti.notebook_path || ti.path, root);
  switch (tool) {
    case 'Read': {
      const a = ti.offset, b = ti.limit;
      return { what: '`' + f + (a ? ':' + a + (b ? '-' + (a + b - 1) : '') : '') + '`' };
    }
    case 'Grep': return { what: '`' + clip(String(ti.pattern || ''), 60) + '`' + (f ? ' in `' + f + '`' : '') };
    case 'Glob': return { what: '`' + clip(String(ti.pattern || ''), 60) + '`' };
    case 'Edit': return { what: '`' + f + '`' + (ti.replace_all ? ' (every match)' : ''), file: f, add: count(ti.new_string), del: count(ti.old_string) };
    case 'MultiEdit': {
      const e = Array.isArray(ti.edits) ? ti.edits : [];
      return { what: '`' + f + '` (' + e.length + ' edits)', file: f,
        add: e.reduce((n, x) => n + count(x.new_string), 0), del: e.reduce((n, x) => n + count(x.old_string), 0) };
    }
    case 'Write': return { what: '`' + f + '`' + (tr && tr.type === 'update' ? ' (rewritten)' : ' (new)'), file: f, add: count(ti.content), del: 0 };
    case 'WebFetch': return { what: clip(String(ti.url || ''), 80) };
    case 'WebSearch': return { what: '"' + clip(String(ti.query || ''), 60) + '"' };
    case 'Task': case 'Agent': return { what: 'subagent: ' + clip(String(ti.description || ti.subagent_type || ''), 60) };
  }
  if (typeof ti.command === 'string') {
    const c = ti.command;
    // Codex edits files with a patch passed through its shell tool. Count it
    // the way a diff would: + lines and - lines, not the headers.
    if (/\*\*\* Begin Patch/.test(c)) {
      const files = (c.match(/^\*\*\* (?:Add|Update|Delete) File: (.+)$/gm) || []).map((l) => l.replace(/^\*\*\* \w+ File: /, ''));
      const body = c.split('\n').filter((l) => !/^\*\*\*/.test(l));
      return { what: 'patch `' + files.join('`, `') + '`', file: files.join(', '),
        add: body.filter((l) => l[0] === '+').length, del: body.filter((l) => l[0] === '-').length };
    }
    return { what: '`' + clip(c.split('\n')[0], 90) + '`' };
  }
  return { what: Object.keys(ti).slice(0, 3).join(', ') };
}

function state(session) {
  return path.join(os.tmpdir(), 'leo-turn-' + String(session).replace(/[^\w.-]/g, '_') + '.json');
}

function main() {
  let input;
  try { input = JSON.parse(readStdin() || '{}'); } catch (e) { return 0; }
  const tool = input.tool_name;
  if (!tool) return 0;
  const root = rootOf(input.cwd || process.cwd());
  const d = describe(tool, input.tool_input || {}, input.tool_response, root);

  const file = traceFile(root);
  if (file) {
    try {
      let text = '';
      try { text = fs.readFileSync(file, 'utf8'); } catch (e) {
        text = '# Trace\n\n' +
          'Written by the runtime after every tool call (`.agents/hooks/trace.js`), not by the agent.\n' +
          'This is what ran, in order. The ▶ and ✓ lines are what the agent says it did; this is the check.\n\n' +
          '| # | time | tool | what | lines |\n|---|------|------|------|-------|\n';
      }
      const n = (text.match(/^\| \d+ \|/gm) || []).length + 1;
      const lines = d.add || d.del ? '+' + (d.add || 0) + ' −' + (d.del || 0) : '';
      const time = new Date().toTimeString().slice(0, 8);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, text + '| ' + n + ' | ' + time + ' | ' + cell(tool) + ' | ' + cell(d.what) + ' | ' + lines + ' |\n');
    } catch (e) { /* a trace must never fail the call */ }
  }

  if (d.add || d.del) {
    const s = state(input.session_id || 'none');
    let t = { lines: 0, files: {} };
    try { t = JSON.parse(fs.readFileSync(s, 'utf8')); } catch (e) { /* first change this reply */ }
    const k = d.file || '?';
    t.lines += (d.add || 0) + (d.del || 0);
    t.files[k] = (t.files[k] || 0) + (d.add || 0) + (d.del || 0);
    try { fs.writeFileSync(s, JSON.stringify(t)); } catch (e) { /* best effort */ }
  }
  return 0;
}

if (require.main === module) process.exitCode = main();
module.exports = { describe, state };
