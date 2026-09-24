'use strict';
// Ponytail — a ruleset appended to AGENTS.md, not a program.
//
// Presence is therefore a property of the repository's own AGENTS.md, and
// specifically of the part leo did NOT write: leo's own tools block names
// every capability including this one, so searching the whole file would
// find the word "ponytail" that `leo agents` just put there and report the
// ruleset installed in a repository that has never seen it.
const fs = require('fs');
const path = require('path');

exports.label = () => 'Ponytail';

exports.present = (ctx) => {
  const f = path.join(ctx.root || '.', 'AGENTS.md');
  let body;
  try { body = fs.readFileSync(f, 'utf8'); } catch (e) { return false; }
  let skip = false;
  const kept = [];
  for (const line of body.split('\n')) {
    if (line.indexOf('leo:tools begin') !== -1) skip = true;
    if (!skip) kept.push(line);
    if (line.indexOf('leo:tools end') !== -1) skip = false;
  }
  return kept.join('\n').toLowerCase().indexOf('ponytail') !== -1;
};

exports.hint = () => [
  'the ruleset:  https://github.com/DietrichGebert/ponytail  -> append AGENTS.md',
  'Claude Code:  /plugin marketplace add DietrichGebert/ponytail',
  '              /plugin install ponytail@ponytail',
];

exports.advice = () => [
  'the plan outranks it: a task that asks for an abstraction gets the abstraction',
  "an honest '-' row in the manifest is still the stronger check",
];

exports.install = () => [
  "printf '\\n' >> AGENTS.md",
  'curl -fsSL https://raw.githubusercontent.com/DietrichGebert/ponytail/main/AGENTS.md >> AGENTS.md',
];

exports.kind = () => 'ambient';
exports.oneline = () => 'Ambient. Nothing to announce, and nothing you can call at a moment.';
