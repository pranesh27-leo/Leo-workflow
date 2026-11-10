#!/usr/bin/env node
'use strict';
// The evidence gate. Claude Code and Codex both run this when the agent is
// about to finish a reply (the Stop hook), and both send it the reply as
// last_assistant_message.
//
// AGENTS.md tells the agent to cite file:line for every claim about the code.
// That is advice, and advice is what fails on a busy turn. This checks the
// two parts of it a program can check, and sends the reply back if either
// fails:
//
//   1. every cited path:line names a file that exists, at a line inside it
//   2. a reply that names a file in this repository cites at least one line
//
// It cannot check that a claim is TRUE. It checks that the evidence the
// claim points at is real, which is what a fabricated explanation lacks.
//
// Node and the standard library only: no shell, no subprocess per file. On
// Windows that is the difference between instant and minutes.

const fs = require('fs');
const os = require('os');
const path = require('path');

// After this many blocks in a row on one session, let the reply through.
// Codex sends stop_hook_active; Claude Code's payload may not, and a gate
// that can block forever is worse than no gate.
const MAX_BLOCKS = 2;

const EXT = 'js|mjs|cjs|ts|tsx|jsx|py|rb|go|rs|java|kt|kts|swift|c|h|cc|cpp|hpp|cs|php|' +
  'scala|sh|bash|zsh|ps1|lua|dart|ex|exs|erl|clj|vue|svelte|sql|json|jsonc|toml|yaml|yml|' +
  'ini|cfg|conf|xml|html|css|scss|md|mdx|txt|gradle|tf|proto|graphql|env|lock';
// A path, then :LINE or :START-END. The look-behind keeps URLs (://) and
// emails out; the extension list keeps host:port out.
const CITE = new RegExp('(?<![\\w/:@.-])((?:[\\w.-]+/)*[\\w.-]+\\.(?:' + EXT + ')):(\\d+)(?:-(\\d+))?\\b', 'g');
const NAMED = new RegExp('(?<![\\w/:@.-])((?:[\\w.-]+/)*[\\w.-]+\\.(?:' + EXT + '))(?![\\w:])', 'g');

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch (e) { return ''; }
}

// The repository root: the nearest directory above cwd holding .git. Paths
// in a reply are repo-relative, and the session may have started deeper.
function rootOf(dir) {
  let d = dir;
  for (;;) {
    if (fs.existsSync(path.join(d, '.git'))) return d;
    const up = path.dirname(d);
    if (up === d) return dir;
    d = up;
  }
}

function resolve(p, cwd, root) {
  for (const base of [cwd, root]) {
    const f = path.resolve(base, p);
    try { if (fs.statSync(f).isFile()) return f; } catch (e) { /* next */ }
  }
  return null;
}

function lineCount(file) {
  const s = fs.readFileSync(file, 'utf8');
  if (s === '') return 0;
  const n = s.split('\n').length;
  return s.endsWith('\n') ? n - 1 : n;
}

// Code blocks are output and examples, not claims: skip them.
function prose(msg) {
  return msg.replace(/```[\s\S]*?```/g, '');
}

function check(msg, cwd) {
  const root = rootOf(cwd);
  const text = prose(msg);
  const problems = [];
  let cited = 0;

  for (const m of text.matchAll(CITE)) {
    cited++;
    const [ref, p, a, b] = m;
    const f = resolve(p, cwd, root);
    if (!f) { problems.push(ref + ': no such file in this repository'); continue; }
    const n = lineCount(f);
    const hi = Math.max(+a, b ? +b : 0);
    if (+a < 1 || hi > n) problems.push(ref + ': ' + p + ' has ' + n + ' lines');
  }

  if (cited === 0) {
    const named = new Set();
    for (const m of text.matchAll(NAMED)) {
      if (resolve(m[1], cwd, root)) named.add(m[1]);
    }
    if (named.size) {
      problems.push('names ' + [...named].join(', ') + ' but cites no line. ' +
        'Every claim about the code needs path:LINE you read this session');
    }
  }
  return problems;
}

function counter(session) {
  return path.join(os.tmpdir(), 'leo-evidence-' + String(session).replace(/[^\w.-]/g, '_'));
}

function main() {
  let input;
  try { input = JSON.parse(readStdin() || '{}'); } catch (e) { return 0; }
  const msg = input.last_assistant_message;
  if (typeof msg !== 'string' || !msg) return 0;

  const cwd = input.cwd || process.cwd();
  const state = counter(input.session_id || 'none');
  const problems = check(msg, cwd);

  if (!problems.length) {
    try { fs.unlinkSync(state); } catch (e) { /* none */ }
    return 0;
  }
  if (input.stop_hook_active) return 0;
  let n = 0;
  try { n = +fs.readFileSync(state, 'utf8') || 0; } catch (e) { /* first */ }
  if (n >= MAX_BLOCKS) {
    try { fs.unlinkSync(state); } catch (e) { /* none */ }
    return 0;
  }
  fs.writeFileSync(state, String(n + 1));

  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason: 'evidence: this reply makes claims about the code that are not backed by real lines.\n- ' +
      problems.join('\n- ') +
      '\nOpen the files, find the actual lines, and cite them as path:LINE. ' +
      'If you cannot establish something from the code, say it is unknown. Never guess. ' +
      '(.agents/skills/evidence/SKILL.md)'
  }) + '\n');
  return 0;
}

process.exitCode = main();
