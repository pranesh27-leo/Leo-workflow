'use strict';
// git. The only subprocess leo still spawns, and the reason the rest of this
// port exists.
//
// Everything leo used to do with awk, sed, grep and wc is now in-process JS.
// What is left is git itself, called once per operation rather than once per
// file. That distinction is the whole Windows story: the old `lines_changed`
// ran `grep` and `wc` once per untracked path, and on Windows a process spawn
// crosses into Win32 through an emulation layer and costs roughly an order of
// magnitude more than it does natively. Thousands of untracked files turned
// that into minutes, on every single leo command, because the session
// document is written from the exit trap.
//
// spawnSync with an argument array, never `shell: true`: no quoting rules, no
// word splitting, no interpreter in the middle that leo does not control, and
// a path with a space in it is simply one argument.

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { tmpDir, isText, countLines } = require('./fsx');

// LEO_TIMING=1 reports every git call and what it cost, on the way out.
//
// This exists because "leo is slow" has now been investigated twice from the
// outside, once over several rounds of guessing, and both times the answer
// was a git call nobody could see. The expensive one is never the obvious
// one: `ls-files --others` against leo's scratch index is a full uncached
// walk of the working tree, and on a large repository it dwarfs everything
// else leo does -- while looking, from the outside, exactly like a hang.
const TIMING = Boolean(process.env.LEO_TIMING);
const timings = [];

function git(args, opts) {
  const o = opts || {};
  const t0 = TIMING ? Date.now() : 0;
  const res = spawnSync('git', args, {
    encoding: 'utf8',
    maxBuffer: 256 * 1024 * 1024,
    windowsHide: true,
    cwd: o.cwd,
    env: o.env ? Object.assign({}, process.env, o.env) : process.env,
  });
  if (TIMING) timings.push({ ms: Date.now() - t0, cmd: 'git ' + args.join(' ') });
  return {
    status: res.status === null ? 1 : res.status,
    stdout: res.stdout || '',
    stderr: res.stderr || '',
    error: res.error,
  };
}

// Reported from the exit hook so the session-document write -- which runs
// after every command and is the thing most likely to be slow -- is in the
// total rather than missing from it.
function reportTimings() {
  if (!TIMING || !timings.length) return;
  const total = timings.reduce((a, t) => a + t.ms, 0);
  process.stderr.write('\nleo: ' + timings.length + ' git call(s), ' + total + 'ms\n');
  for (const t of timings) {
    process.stderr.write('  ' + String(t.ms).padStart(6) + 'ms  ' + t.cmd + '\n');
  }
}

// gitLines — stdout split into non-empty lines. git's porcelain and plumbing
// both emit newline-terminated lists; the trailing empty string after the
// final newline is never a path.
function gitLines(args, opts) {
  const r = git(args, opts);
  if (r.status !== 0) return [];
  return r.stdout.split('\n').filter((l) => l !== '');
}

function repoRoot() {
  const r = git(['rev-parse', '--show-toplevel']);
  if (r.status !== 0) return '';
  return r.stdout.trim();
}

// baseIndex — a scratch git index seeded from <base>, returned as a path.
// The caller deletes it.
//
// Why not just use the real index: a `leo record` base is a tree object
// holding files that are still untracked in the developer's index, and
// `git diff <tree>` reports those as *deleted* -- the tree has them, the
// index does not. The first fix for that was for `leo record` to `git add -A`,
// which made the diff right and the repository wrong: an ordinary
// `git commit` after a record swept the whole recorded change into it, under
// that commit's message, and `leo commit` then had nothing left to land.
//
// Seeding a throwaway index from the base instead gets the same correct diff
// and never touches what the developer has staged. The index is theirs.
function baseIndex(base) {
  const p = path.join(tmpDir(), 'leo-idx-' + process.pid + '-' + Math.random().toString(36).slice(2));
  git(['read-tree', base || 'HEAD'], { env: { GIT_INDEX_FILE: p } });
  return p;
}

function dropIndex(p) {
  try { fs.unlinkSync(p); } catch (e) { /* read-tree may never have made it */ }
}

// untracked — new files git can see, honouring .gitignore.
function untracked(indexFile) {
  return gitLines(['ls-files', '--others', '--exclude-standard'],
    indexFile ? { env: { GIT_INDEX_FILE: indexFile } } : undefined);
}

// notBookkeeping — drop leo's own plan files from a list of paths.
//
// `.leo/plans/` is tracked, unlike everything else leo writes, because a plan
// is the reasoning behind a change and outlives it. That makes the plan and
// its task files show up in `git diff` like any other tracked file -- so the
// manifest demanded a row for the plan that the manifest is scoped by, with a
// "Why" and an "If deleted" for a document whose answer to both is "it is the
// question you are asking", and the budget measured the change against an
// estimate the change's own prose was inflating.
//
// The rule, stated once: **the plan describing a change is not part of the
// change it describes.** Nothing else under `.leo/` is excluded. `.leo/rules/`
// and `.leo/integrations/` are repository code somebody wrote on purpose, they
// are reviewed like any other file, and a blanket `.leo/` filter here would
// quietly stop reviewing them.
function notBookkeeping(paths) {
  return paths.filter((p) => !p.startsWith('.leo/plans/'));
}

// changeStats <base> — the file list and the line count, from ONE scan.
//
// Both numbers come from the same three git calls: a scratch index, one
// `diff --numstat` (which carries the paths as well as the counts, so there
// is no need to ask for --name-only separately) and one untracked scan.
//
// The combined form exists because the separate ones were being called in
// pairs, and each built its own scratch index and ran its own untracked
// scan -- six git calls for three calls' worth of answers. That is cheap on
// a small repository and is not cheap at all on a large one: `ls-files
// --others` against a *scratch* index is a full, uncached walk of the
// working tree, because a brand new index carries none of the caching
// extensions (untracked-cache, fsmonitor) that the real `.git/index`
// accumulates. Doing that walk twice per command, on every command, is what
// a leo that "hangs" is actually doing.
function changeStats(base) {
  const b = base || 'HEAD';
  const idx = baseIndex(b);
  try {
    const env = { GIT_INDEX_FILE: idx };
    const files = [];
    let lines = 0;

    const numstat = git(['diff', '--numstat', b], { env });
    if (numstat.status === 0) {
      for (const line of numstat.stdout.split('\n')) {
        if (line === '') continue;
        const f = line.split('\t');
        if (f.length < 3) continue;
        if (f[2].startsWith('.leo/plans/')) continue;
        files.push(f[2]);
        // A binary diff is "-" in both columns; it has a row but no count.
        if (f[0] === '-' || f[1] === '-') continue;
        lines += (parseInt(f[0], 10) || 0) + (parseInt(f[1], 10) || 0);
      }
    }

    for (const f of notBookkeeping(untracked(idx))) {
      files.push(f);
      // Untracked files have no diff to measure, so they count their whole
      // length -- but only if they are text, which is why isText is consulted
      // before countLines rather than after.
      if (isText(f)) lines += countLines(f);
    }

    return { files: Array.from(new Set(files)).sort(), lines };
  } finally {
    dropIndex(idx);
  }
}

// changed <base> — every file that differs from <base>, plus files that did
// not exist in it at all. Sorted and de-duplicated, as `sort -u` did.
function changed(base) {
  return changeStats(base).files;
}

// linesChanged <base> — added + removed across tracked and untracked files.
function linesChanged(base) {
  return changeStats(base).lines;
}

module.exports = {
  git, gitLines, repoRoot, baseIndex, dropIndex,
  untracked, notBookkeeping, changeStats, changed, linesChanged,
  reportTimings,
};
