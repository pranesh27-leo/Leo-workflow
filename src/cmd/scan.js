'use strict';
// desc: turn the diff into a manifest, one row per hunk
// usage: leo scan [<base>]
//
// 500 lines of diff become ~20 rows, and each row has to earn its place: what
// it is, why it exists, and what breaks if it is deleted. That is the whole
// exercise, and an honest "-" in the Task column is worth more than an
// invented id.

const fs = require('fs');
const { info, dim, ok, die } = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const { isFile, isText, countLines, mkdirp } = require('../lib/fsx');
const { git, baseIndex, dropIndex, untracked, notBookkeeping, linesChanged } = require('../lib/repo');
const { recordBase } = require('../lib/records');
const { planEst } = require('../lib/plan');

// hunkRows — parse `git diff -U0` into one row per hunk.
//
// -U0 so each hunk is exactly the changed lines, with no shared context
// gluing two unrelated edits into one row. The file name comes from the
// "+++ b/" line rather than "diff --git", because a rename has two different
// names on that line and the one that matters is where the code is now.
function parseHunks(diff) {
  const rows = [];
  let file = '', start = '', add = 0, del = 0, open = false;

  const flush = () => {
    // The plan describing this change is not part of the change it describes.
    // `.leo/plans/` is tracked, so it arrives in the diff like anything else,
    // and a row asking "why does this hunk exist" about the document that
    // answers that question for every other row is circular.
    if (open && file.indexOf('.leo/plans/') !== 0) {
      rows.push({ file, start, add, del });
    }
    open = false; add = 0; del = 0;
  };

  for (const line of diff.split('\n')) {
    if (line.indexOf('diff --git ') === 0) { flush(); continue; }
    if (line.indexOf('+++ b/') === 0) { file = line.slice(6); continue; }
    if (line.indexOf('--- ') === 0) continue;
    if (line.indexOf('@@') === 0) {
      flush();
      const m = /^@@ [^+]*\+([0-9]+)/.exec(line);
      start = m ? m[1] : '';
      open = true;
      continue;
    }
    if (open && line[0] === '+') add++;
    else if (open && line[0] === '-') del++;
  }
  flush();
  return rows;
}

function run(ctx) {
  needRepo(ctx);

  // The default is HEAD until a cycle has been recorded, and the tree that
  // cycle left behind after. Otherwise a second cycle re-enumerates the
  // first one's hunks: nothing landed in between, so HEAD is still the start
  // of the change rather than the start of this part of it.
  const base = ctx.argv[0] || recordBase(ctx.records);
  if (git(['rev-parse', '--verify', '--quiet', base]).status !== 0) {
    die("'" + base + "' is not a valid git revision");
  }

  if (isFile(ctx.manifest)) {
    die(ctx.manifest + ' already exists — finish or delete it first');
  }

  const est = planEst(ctx.plan);
  const actual = linesChanged(base);

  const out = [];
  out.push('# Manifest');
  out.push('');
  // Only worth recording when it is not the obvious one -- this text ends up
  // in the commit message, and noise there costs more than it saves.
  if (base !== 'HEAD') { out.push('Base: ' + base); out.push(''); }
  out.push('| # | Hunk | Delta | Task | Why | If deleted |');
  out.push('|---|------|-------|------|-----|------------|');

  const idx = baseIndex(base);
  let n = 0;
  try {
    const diff = git(['diff', '-U0', base], { env: { GIT_INDEX_FILE: idx } });
    for (const r of parseHunks(diff.stdout)) {
      n++;
      out.push('| ' + n + ' | `' + r.file + ':' + r.start + '` | +' + r.add + '/-' + r.del + ' |  |  |  |');
    }

    // A new file is one row: git has no hunks to split it by, so the reviewer
    // reads the file. Binaries get a row too, but no line count to pretend
    // with.
    for (const f of notBookkeeping(untracked(idx))) {
      if (isText(f)) out.push('| NEW | `' + f + '` | +' + countLines(f) + ' |  |  |  |');
      else out.push('| NEW | `' + f + '` | binary |  |  |  |');
    }
  } finally {
    dropIndex(idx);
  }

  out.push('');
  out.push('Budget: est ' + (est || '?') + ' LOC / actual ' + actual + ' LOC');
  out.push('Tests: <command> -- <paste the real output>');

  const body = out.join('\n') + '\n';

  // Counted from the rows rather than by grepping the file back: the header
  // row starts with "| " too, and the shell subtracted one to compensate.
  const hunks = body.split('\n').filter((l) => l.indexOf('| ') === 0).length - 1;
  if (hunks <= 0) {
    die('nothing has changed since ' + base + ' — nothing to review');
  }

  mkdirp(ctx.leoDir);
  fs.writeFileSync(ctx.manifest, body);

  ok('wrote .leo/manifest.md (' + hunks + ' hunks, ' + actual + ' lines vs est ' + (est || '?') + ')');
  info('');
  info('Now fill in Task / Why / If deleted for every row, from the diff:');
  dim('  git diff ' + base + '        <- read this, not your memory of what you wrote');
  dim("  Never invent a task ID to make a hunk look justified. An honest '-' is");
  dim('  the entire value of the exercise.');
  dim('  Then: leo check');
  return 0;
}

module.exports = { run };
