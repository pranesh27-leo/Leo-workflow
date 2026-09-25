#!/usr/bin/env node
'use strict';
// leo init — copy the harness into a repository, once.
//
// This is the whole program, and it is a copier. leo used to be a workflow
// CLI that scanned diffs, enforced a manifest and assembled commit messages;
// that is gone, and what replaced it is the markdown it used to generate.
// The reasoning is in README.md.
//
// So the only thing left to solve is distribution: getting eleven files into
// somebody's repository on Windows, macOS and Linux identically. `npx
// leo-workflow init` does that and is then never needed again. Nothing here
// runs during your work, nothing watches, nothing checks.
//
// Node, because npm is the one installer present on every machine that has
// an agent on it, and npm generates its own .cmd and .ps1 shims from this
// file's shebang -- pointing them at a Node program is what stops Windows
// choosing an interpreter leo does not control.

const fs = require('fs');
const path = require('path');

const HOME = path.resolve(__dirname, '..');
const SRC = path.join(HOME, '.agents');

// Where each file lands. AGENTS.md goes to the repository root because that
// is the one path every agent runtime already loads; everything else lives
// under .agents/ so there is exactly one directory to read, delete or
// inspect.
//
// The .claude/skills/ copies are the one vendor-specific thing here. Claude
// Code reads skills from that path and nowhere else, and a skill nobody's
// runtime loads is the bug this vendoring exists to fix. Any other runtime
// is pointed at .agents/skills/, which is the canonical copy.
const SKILLS = ['grill-me', 'tdd', 'ponytail', 'caveman', 'humanizer'];

// Three of the five are somebody else's work, vendored under their own
// licence, and the licence travels in the same directory as the file it
// covers -- not one LICENSE at the top for all of them, which would leave a
// reader guessing which terms applied to what.
const LICENSED = ['grill-me', 'ponytail', 'humanizer'];

function plan() {
  const out = [['AGENTS.md', 'AGENTS.md']];
  out.push(['leo.md', path.join('.agents', 'leo.md')]);
  for (const t of ['graph', 'rtk']) {
    out.push([path.join('tools', t + '.md'), path.join('.agents', 'tools', t + '.md')]);
  }
  for (const s of SKILLS) {
    const rel = path.join('skills', s, 'SKILL.md');
    out.push([rel, path.join('.agents', rel)]);
    out.push([rel, path.join('.claude', 'skills', s, 'SKILL.md')]);
  }
  for (const s of LICENSED) {
    const rel = path.join('skills', s, 'LICENSE');
    out.push([rel, path.join('.agents', rel)]);
    out.push([rel, path.join('.claude', 'skills', s, 'LICENSE')]);
  }
  return out;
}

function main(argv) {
  const cmd = argv[0];
  const force = argv.indexOf('--force') !== -1;

  if (cmd === '--version' || cmd === '-v') {
    process.stdout.write(fs.readFileSync(path.join(HOME, 'VERSION'), 'utf8').trim() + '\n');
    return 0;
  }

  if (cmd !== 'init' || argv.filter((a) => a[0] !== '-').length !== 1) {
    process.stderr.write(
      'leo init            copy the harness into this directory\n' +
      'leo init --force    overwrite files that already exist\n' +
      '\n' +
      'That is the whole command. leo does not run during your work --\n' +
      'the harness is markdown, and AGENTS.md is where it starts.\n');
    return cmd === 'init' ? 1 : (cmd === undefined || cmd === 'help' || cmd === '--help' ? 0 : 1);
  }

  let wrote = 0, kept = 0;
  for (const [from, to] of plan()) {
    const src = path.join(SRC, from);
    if (!fs.existsSync(src)) {
      process.stderr.write('ERR  missing from this install: ' + from + '\n');
      return 1;
    }
    if (fs.existsSync(to) && !force) {
      process.stderr.write('  skip    ' + to + ' (exists)\n');
      kept++;
      continue;
    }
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(src, to);
    process.stderr.write('  write   ' + to + '\n');
    wrote++;
  }

  process.stderr.write('\nok   ' + wrote + ' written, ' + kept + ' kept\n');
  if (kept && !force) {
    process.stderr.write('     leo init --force overwrites the kept ones\n');
  }
  process.stderr.write(
    '\n  1. open AGENTS.md and fill in the session block at the top:\n' +
    '     the mode, and whether this is TDD work\n' +
    '  2. point your agent at AGENTS.md\n' +
    '  3. the stages are in .agents/leo.md — that is the whole workflow\n' +
    '\n  Nothing to run. leo is not needed again in this repository.\n');
  return 0;
}

process.exitCode = main(process.argv.slice(2));
