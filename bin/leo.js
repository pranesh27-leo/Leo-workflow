#!/usr/bin/env node
'use strict';
// leo init — copy the harness into a repository, once.
//
// This is the whole program, and it is a copier. leo used to be a workflow
// CLI that scanned diffs, enforced a manifest and assembled commit messages;
// that is gone, and what replaced it is the markdown it used to generate.
// The reasoning is in README.md.
//
// So the only thing left to solve is distribution: getting the files into
// somebody's repository on Windows, macOS and Linux identically. `npx
// leo-workflow init` does that and is then never needed again. Nothing in
// this file runs during your work; the hooks it copies are what run.
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
const SKILLS = ['grill-me', 'tdd', 'ponytail', 'humanizer', 'feynman', 'evidence', 'points', 'asd-ste100', 'replan'];

// Four of the nine are somebody else's work, vendored under their own
// licence, and the licence travels in the same directory as the file it
// covers -- not one LICENSE at the top for all of them, which would leave a
// reader guessing which terms applied to what.
const LICENSED = ['grill-me', 'ponytail', 'humanizer', 'asd-ste100'];

// Files a vendored skill reads beside its SKILL.md. asd-ste100's method
// points at its rule summary, its examples and its linter by relative path,
// so they travel with it or the skill points at nothing.
const EXTRA = {
  'asd-ste100': [
    path.join('references', 'writing-rules.md'),
    path.join('examples', 'before-after.md'),
    path.join('examples', 'linter-edge-cases.md'),
    path.join('scripts', 'ste-lint.py'),
  ],
};

// The three repository documents land at the root, beside AGENTS.md, because
// that is where a human looks for them. They ship as placeholders to be
// filled in: an empty ARCHITECTURE.md is a prompt, and a missing one is a
// dangling reference from AGENTS.md.
const DOCS = ['CONTEXT.md', 'ARCHITECTURE.md', 'RULES.md'];

// The work-product templates stay under .agents/templates/ and are copied by
// the AGENT when it reaches that stage -- never by init. Shipping a
// pre-made .agents/goals/G1/ would be shipping half a change.
const TEMPLATES = ['goal.md', 'plan.md', 'task.md', 'manifest.md', 'review.md'];

// The things that run. The skills are advice; these are the gates behind
// the checks a program can make, run by the agent's runtime whatever the
// model decides: trace.js after a tool call (what really ran), and at the end of a reply
// check-evidence.js (citations are real) and budget.js (one reply stays
// readable). Each runtime reads its hooks from its own path, so each gets a
// registration. An existing settings file is kept like every other file,
// and init says so -- merging into somebody's settings is not a copier's job.
const HOOKS = [
  [path.join('hooks', 'check-evidence.js'), path.join('.agents', 'hooks', 'check-evidence.js')],
  [path.join('hooks', 'trace.js'), path.join('.agents', 'hooks', 'trace.js')],
  [path.join('hooks', 'budget.js'), path.join('.agents', 'hooks', 'budget.js')],
  [path.join('hooks', 'claude-settings.json'), path.join('.claude', 'settings.json')],
  [path.join('hooks', 'codex-hooks.json'), path.join('.codex', 'hooks.json')],
];

function plan() {
  const out = [['AGENTS.md', 'AGENTS.md']];
  out.push(['leo.md', path.join('.agents', 'leo.md')]);
  for (const d of DOCS) {
    out.push([path.join('templates', d), d]);
  }
  for (const t of TEMPLATES) {
    out.push([path.join('templates', t), path.join('.agents', 'templates', t)]);
  }
  for (const t of ['graph', 'rtk', 'understand']) {
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
  for (const s of Object.keys(EXTRA)) {
    for (const f of EXTRA[s]) {
      const rel = path.join('skills', s, f);
      out.push([rel, path.join('.agents', rel)]);
      out.push([rel, path.join('.claude', 'skills', s, f)]);
    }
  }
  // The reviewer that never saw the work. Claude Code reads subagents from
  // .claude/agents/; the .agents/ copy is the canonical one, like the skills.
  out.push([path.join('agents', 'leo-reviewer.md'), path.join('.agents', 'agents', 'leo-reviewer.md')]);
  out.push([path.join('agents', 'leo-reviewer.md'), path.join('.claude', 'agents', 'leo-reviewer.md')]);
  for (const h of HOOKS) out.push(h);
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
  const keptHooks = [];
  for (const [from, to] of plan()) {
    const src = path.join(SRC, from);
    if (!fs.existsSync(src)) {
      process.stderr.write('ERR  missing from this install: ' + from + '\n');
      return 1;
    }
    if (fs.existsSync(to) && !force) {
      process.stderr.write('  skip    ' + to + ' (exists)\n');
      kept++;
      if (/settings\.json$|hooks\.json$/.test(to)) keptHooks.push(to);
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
  for (const h of keptHooks) {
    process.stderr.write('     ' + h + ' was kept: add the hooks from .agents/hooks/ to it by hand\n');
  }
  process.stderr.write(
    '\n  1. open AGENTS.md and fill in the session block at the top:\n' +
    '     the mode, whether this is TDD work, and how many lines\n' +
    '     you can read in one reply\n' +
    '  2. point your agent at AGENTS.md\n' +
    '  3. the stages are in .agents/leo.md — that is the whole workflow\n' +
    '  4. Codex: run /hooks once to trust .codex/hooks.json\n' +
    '\n  leo is not needed again. What runs are the hooks in .agents/hooks/,\n' +
    '  called by your agent: the trace after a tool call, and the evidence\n' +
    '  and budget checks at the end of each reply.\n');
  return 0;
}

process.exitCode = main(process.argv.slice(2));
