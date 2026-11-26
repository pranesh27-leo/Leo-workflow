#!/usr/bin/env node
'use strict';
// The guard. Claude Code and Codex both run this before a tool call (the
// PreToolUse hook), and both send it the call as tool_name and tool_input.
//
// AGENTS.md has three standing orders that are about safety, not taste:
// never commit, never install, never read a secret. As lines in a markdown
// file they are advice, and advice is what a model skips on a busy turn. A
// rule with no exceptions belongs where the runtime enforces it, so this
// turns those three into a "deny" the agent cannot talk its way past:
//
//   1. git commit / git push      the commit is the developer's
//   2. installs                   never install, and say whether each package
//                                 is already a dependency or new. A NEW name
//                                 is the one to check: models invent package
//                                 names, and attackers register the ones
//                                 they invent (slopsquatting)
//   3. secrets                    .env, keys and token files stay out of the
//                                 context: what the agent reads can end up
//                                 in a reply, a log or a commit
//
// It is a guard, not a sandbox. It reads the command text, so a command built
// to hide what it does (eval, base64, a script file) gets past it. The
// boundary that holds against that is the runtime's sandbox, not this file.
//
// Node and the standard library only, like the evidence hook.

const fs = require('fs');
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

function read(f) {
  try { return fs.readFileSync(f, 'utf8'); } catch (e) { return ''; }
}

// ---------------------------------------------------------------- secrets

// A secret by its name. .env.example and friends are templates, written to
// be read, so they pass.
const SECRET = /(^|[\\/])(\.env(\.[\w-]+)?|\.npmrc|\.pypirc|\.netrc|id_(rsa|dsa|ecdsa|ed25519)|[\w.-]+\.(pem|key|p12|pfx))$/i;
const TEMPLATE = /\.(example|sample|template|dist)$/i;
const isSecret = (p) => SECRET.test(p) && !TEMPLATE.test(p);

// Commands that print a file. `source .env && npm test` uses a secret without
// showing it to the model, so it is not blocked; `cat .env` shows it. cp is
// not here: `cp .env.example .env` is how most projects are set up.
const READERS = new Set(['cat', 'less', 'more', 'head', 'tail', 'bat', 'grep', 'rg',
  'sed', 'awk', 'strings', 'xxd', 'od', 'type', 'get-content', 'gc', 'base64']);

// ---------------------------------------------------------------- commands

// Split a command line into its simple commands. Not a shell parser: quotes
// are honoured, enough that `git commit -m "a && b"` is one command.
function segments(cmd) {
  const out = [];
  let cur = '', q = '';
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i], two = cmd.slice(i, i + 2);
    if (q) { if (c === q) q = ''; cur += c; continue; }
    if (c === '"' || c === "'") { q = c; cur += c; continue; }
    if (two === '&&' || two === '||') { out.push(cur); cur = ''; i++; continue; }
    // `2>&1` is a redirect, not a background job: an & touching > stays put.
    const redirect = c === '&' && (cmd[i - 1] === '>' || cmd[i + 1] === '>');
    if (!redirect && (c === ';' || c === '|' || c === '\n' || c === '&' || c === '(' || c === ')')) { out.push(cur); cur = ''; continue; }
    cur += c;
  }
  out.push(cur);
  return out.map(words).filter((w) => w.length);
}

function words(s) {
  const w = (s.match(/"[^"]*"|'[^']*'|\S+/g) || []).map((x) => x.replace(/^["']|["']$/g, ''));
  // Drop what only wraps the real command: FOO=1, sudo, env, command, time.
  while (w.length && (/^\w+=/.test(w[0]) || ['sudo', 'env', 'command', 'exec', 'time', 'nohup'].includes(w[0]))) w.shift();
  return w;
}

// The git subcommand, past -C <dir> and -c <k=v>.
function gitSub(w) {
  let i = 1;
  while (i < w.length && w[i][0] === '-') i += (w[i] === '-C' || w[i] === '-c') ? 2 : 1;
  return w[i] || '';
}

// Each installer: how to recognise it, and which ecosystem its names are in.
// `npx x` and `uvx x` are installs too: they download x and run it, which is
// exactly the moment a hallucinated name does its damage.
function install(w) {
  const [a, b, c] = w;
  // The names after the subcommand: not flags, and not a flag's value
  // (`-r requirements.txt`, `--prefix dir`).
  const VALUED = new Set(['-r', '-c', '-e', '-i', '-t', '--requirement', '--constraint', '--editable',
    '--index-url', '--extra-index-url', '--target', '--prefix', '--registry', '--root']);
  const rest = (n) => w.slice(n).filter((x, i, all) => x[0] !== '-' && !VALUED.has(all[i - 1]));
  if (['npm', 'pnpm', 'yarn', 'bun'].includes(a) && ['install', 'i', 'add', 'ci'].includes(b)) return { eco: 'npm', pkgs: rest(2) };
  if (['npx', 'bunx'].includes(a) || (a === 'pnpm' && b === 'dlx')) return { eco: 'npm', pkgs: rest(a === 'pnpm' ? 2 : 1).slice(0, 1), run: true };
  if (/^pip3?$/.test(a) && b === 'install') return { eco: 'pypi', pkgs: rest(2) };
  if (/^python3?$/.test(a) && b === '-m' && c === 'pip' && w[3] === 'install') return { eco: 'pypi', pkgs: rest(4) };
  if (a === 'uv' && (b === 'add' || (b === 'pip' && c === 'install'))) return { eco: 'pypi', pkgs: rest(b === 'add' ? 2 : 3) };
  if (a === 'uvx' || (a === 'pipx' && b === 'run')) return { eco: 'pypi', pkgs: rest(a === 'uvx' ? 1 : 2).slice(0, 1), run: true };
  if (a === 'poetry' && b === 'add') return { eco: 'pypi', pkgs: rest(2) };
  if (a === 'cargo' && (b === 'add' || b === 'install')) return { eco: 'cargo', pkgs: rest(2) };
  if (a === 'go' && (b === 'get' || b === 'install')) return { eco: 'go', pkgs: rest(2) };
  if (a === 'gem' && b === 'install') return { eco: 'gem', pkgs: rest(2) };
  if (['brew', 'winget', 'choco', 'scoop', 'apt', 'apt-get', 'dnf', 'yum'].includes(a) && b === 'install') return { eco: 'system', pkgs: rest(2) };
  return null;
}

// The name as the manifest writes it: express@4 -> express, numpy==1.2 -> numpy,
// @scope/x@1 -> @scope/x.
function bare(p, eco) {
  if (eco === 'npm') return p.replace(/^(@?[^@]+).*$/, '$1');
  if (eco === 'pypi') return p.replace(/\[.*$/, '').replace(/[=<>~!;].*$/, '').toLowerCase().replace(/_/g, '-');
  if (eco === 'go') return p.replace(/@.*$/, '');
  return p;
}

// Is this name already a dependency here? Read from the manifests the
// repository has, not from a registry: the guard never touches the network.
function declared(name, eco, root) {
  if (eco === 'npm') {
    try {
      const j = JSON.parse(read(path.join(root, 'package.json')) || '{}');
      if ([j.dependencies, j.devDependencies, j.optionalDependencies, j.peerDependencies]
        .some((d) => d && Object.prototype.hasOwnProperty.call(d, name))) return 'package.json';
    } catch (e) { /* unreadable manifest: treat as not declared */ }
    if (fs.existsSync(path.join(root, 'node_modules', '.bin', name))) return 'node_modules/.bin';
    return '';
  }
  const files = {
    pypi: ['requirements.txt', 'requirements-dev.txt', 'pyproject.toml', 'setup.cfg', 'Pipfile'],
    cargo: ['Cargo.toml'], go: ['go.mod'], gem: ['Gemfile'],
  }[eco] || [];
  for (const f of files) {
    const t = read(path.join(root, f)).toLowerCase().replace(/_/g, '-');
    const n = name.toLowerCase().replace(/_/g, '-').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (t && new RegExp('(^|[\\s"\'\\[,])' + n + '($|[\\s"\'=<>~!\\],;@\\[])', 'm').test(t)) return f;
  }
  return '';
}

// ---------------------------------------------------------------- the rules

function judge(input) {
  const tool = input.tool_name || '';
  const ti = input.tool_input || {};
  const cwd = input.cwd || process.cwd();
  const root = rootOf(cwd);

  // File tools: only the secret rule applies.
  if (typeof ti.file_path === 'string' || typeof ti.path === 'string') {
    const p = ti.file_path || ti.path;
    if (/^(Read|Edit|Write|MultiEdit|NotebookEdit|Grep)$/.test(tool) && isSecret(p)) {
      return 'guard: ' + path.basename(p) + ' holds secrets. Do not read or write it: whatever you read can end up in a reply, ' +
        'a log or a commit. Use the variable by name, or ask the developer for the one value you need.';
    }
    return '';
  }

  const cmd = ti.command;
  if (typeof cmd !== 'string') return '';

  for (const w of segments(cmd)) {
    if (w[0] === 'git' && /^(commit|push)$/.test(gitSub(w))) {
      return 'guard: `git ' + gitSub(w) + '` is the developer\'s. Draft the commit message, show it, and stop ' +
        '(.agents/leo.md, stage 11).';
    }

    if (READERS.has(w[0].toLowerCase())) {
      const s = w.slice(1).find((x) => x[0] !== '-' && isSecret(x));
      if (s) {
        return 'guard: `' + w[0] + ' ' + s + '` would put secrets into the conversation. Use the variable by name, ' +
          'or ask the developer for the one value you need.';
      }
    }

    const ins = install(w);
    if (ins) {
      const lines = ins.pkgs.map((p) => {
        const name = bare(p, ins.eco);
        if (ins.eco === 'system') return '  ' + name + ': a system package. The developer decides.';
        const where = declared(name, ins.eco, root);
        return where
          ? '  ' + name + ': already a dependency (' + where + ').'
          : '  ' + name + ': NEW. It is in no manifest here. Models invent package names, and attackers publish ' +
            'under the names they invent. Confirm it exists, who publishes it, and that it is the one you mean.';
      });
      return 'guard: never install (AGENTS.md, standing orders). Show the developer this command and let them run it:\n' +
        '  ' + w.join(' ') + '\n' +
        (lines.length ? lines.join('\n') : '  no package named: this installs what the manifests or the lockfile list.');
    }
  }
  return '';
}

function main() {
  let input;
  try { input = JSON.parse(readStdin() || '{}'); } catch (e) { return 0; }
  const reason = judge(input);
  if (reason) {
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason },
    }) + '\n');
  }
  return 0;
}

if (require.main === module) process.exitCode = main();
module.exports = { judge, segments };
