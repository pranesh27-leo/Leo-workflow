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
// A path, then :LINE or :START-END. Separators are / or \\ (Windows), and
// the path may be absolute (/x, C:\\x, ~/x). The look-behind keeps URLs (://)
// and emails out; the extension list keeps host:port out.
const PATH = '((?:[A-Za-z]:[\\\\/]|~[\\\\/]|[\\\\/])?(?:[\\w.-]+[\\\\/])*[\\w.-]+\\.(?:' + EXT + '))';
const EDGE = '(?<![\\w:@.\\\\/-])';
const CITE = new RegExp(EDGE + PATH + ':(\\d+)(?:-(\\d+))?\\b', 'g');
const NAMED = new RegExp(EDGE + PATH + '(?![\\w:])', 'g');

// Directories never worth searching for a cited file.
const SKIP = new Set(['.git', 'node_modules', '.venv', 'venv', '__pycache__', 'dist', 'target', '.next']);
const WALK_LIMIT = 20000;

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

function isFile(f) {
  try { return fs.statSync(f).isFile(); } catch (e) { return false; }
}

// Every file under cwd, once, bounded. Only built when a cited path does not
// resolve directly: agents cite relative to a subproject as often as to the
// root. Plain fs calls, no subprocess -- see the note at the top.
let index = null;
function walk(dir) {
  if (index) return index;
  index = [];
  const stack = [dir];
  while (stack.length && index.length < WALK_LIMIT) {
    const d = stack.pop();
    let ents;
    try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch (e) { continue; }
    for (const e of ents) {
      const f = path.join(d, e.name);
      if (e.isDirectory()) { if (!SKIP.has(e.name)) stack.push(f); }
      else if (e.isFile()) index.push(f);
    }
  }
  return index;
}

function resolve(raw, cwd, root) {
  let p = raw.replace(/\\/g, '/');
  if (p.startsWith('~/')) p = path.join(os.homedir(), p.slice(2));
  if (path.isAbsolute(p) || /^[A-Za-z]:\//.test(p)) return isFile(p) ? p : null;
  for (const base of [cwd, root, path.dirname(root)]) {
    const f = path.resolve(base, p);
    if (isFile(f)) return f;
  }
  if (p.startsWith('../')) return null;
  const tail = path.sep + path.normalize(p);
  const hits = walk(cwd).filter((f) => f.endsWith(tail));
  return hits.length === 1 ? hits[0] : null;
}

function linesOf(file) {
  const s = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
  if (s === '') return [];
  const l = s.split('\n');
  if (s.endsWith('\n')) l.pop();
  return l;
}

// A quote right after a citation: `path:12` `the code`. Only a separator may
// sit between them, so "`a.js:2` calls `foo`" is a claim, not a quote.
const QUOTE = /^`?\s*(?:[—:,-]\s*)?`([^`\n]{3,})`/;
const squash = (t) => t.replace(/\s+/g, ' ').trim();

// The quote has to be on the cited lines, give or take two: line numbers
// drift by a line or two between reading a file and writing the reply.
function quoteFound(lines, a, b, q) {
  const lo = Math.max(0, a - 3), hi = Math.min(lines.length, (b || a) + 2);
  return squash(lines.slice(lo, hi).join(' ')).includes(squash(q));
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
    if (!f) {
      problems.push(ref + ': no such file, looked from ' + cwd +
        '. If it is elsewhere, cite it by a path that works from there (absolute, or ../other/x)');
      continue;
    }
    const lines = linesOf(f);
    const n = lines.length;
    const hi = Math.max(+a, b ? +b : 0);
    if (+a < 1 || hi > n) { problems.push(ref + ': ' + p + ' has ' + n + ' lines'); continue; }
    const q = QUOTE.exec(text.slice(m.index + ref.length));
    if (q && !quoteFound(lines, +a, b ? +b : 0, q[1])) {
      problems.push(ref + ': the quoted `' + q[1] + '` is not on those lines');
    }
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
  let n = 0;
  try { n = +fs.readFileSync(state, 'utf8') || 0; } catch (e) { /* first */ }
  // stop_hook_active: Codex says this reply is already the retry. Same rule
  // as running out of tries: let it through, and say so.
  if (input.stop_hook_active || n >= MAX_BLOCKS) {
    // Let it through, but say so. A reply that failed the check and was let
    // go must not look the same as one that passed.
    try { fs.unlinkSync(state); } catch (e) { /* none */ }
    process.stdout.write(JSON.stringify({
      systemMessage: 'evidence check gave up. These citations are still not backed by real lines: ' + problems.join(' | ')
    }) + '\n');
    return 0;
  }
  fs.writeFileSync(state, String(n + 1));

  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason: 'evidence: this reply makes claims about the code that are not backed by real lines.\n- ' +
      problems.join('\n- ') +
      '\nOpen the files, find the actual lines, and cite them as path:LINE. ' +
      'If you cannot establish something from the code, say it is unknown. Never guess. ' +
      'Do not repeat the reply: the developer has already read it. ' +
      'Send only the corrected points, each with its citation. ' +
      '(.agents/skills/evidence/SKILL.md)'
  }) + '\n');
  return 0;
}

process.exitCode = main();
