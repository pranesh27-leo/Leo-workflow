'use strict';
// Recorded-but-unlanded cycles, and the git trees they left behind.
//
// `leo record` files a cycle's message under .leo/commits/ without committing
// anything. `leo commit` reads them all and lands one commit. Between those
// two, nothing is in git -- which is the whole point of the loop, and the
// reason a record has to carry its own base.

const fs = require('fs');
const path = require('path');
const { readIfFile, isDir, tmpDir } = require('./fsx');
const { git } = require('./repo');

function records(recordsDir) {
  if (!isDir(recordsDir)) return [];
  return fs.readdirSync(recordsDir)
    .filter((n) => n.endsWith('.md'))
    .sort()
    .map((n) => path.join(recordsDir, n));
}

function recordCount(recordsDir) {
  return records(recordsDir).length;
}

// recordNextId — zero-padded so the directory listing sorts in the order the
// cycles actually happened. 010 after 009, not between 001 and 002.
function recordNextId(recordsDir) {
  const n = records(recordsDir).length + 1;
  return String(n).padStart(3, '0');
}

// recordField <file> <name> — one `Name: value` header line from a record.
function recordField(file, name) {
  const body = readIfFile(file);
  if (body === null) return '';
  const re = new RegExp('^' + name + ': *(.*)$');
  for (const line of body.split('\n')) {
    const m = re.exec(line);
    if (m) return m[1];
  }
  return '';
}

// recordBase — what the next `leo scan` should diff against.
//
// Without a landed commit there is no HEAD meaning "everything before this
// cycle", so each record carries the tree it left behind and the next scan
// starts from that. Otherwise cycle two's manifest would re-enumerate every
// hunk cycle one already accounted for, and the budget check would measure
// the whole change against one task's estimate.
function recordBase(recordsDir) {
  const all = records(recordsDir);
  if (all.length === 0) return 'HEAD';
  const tree = recordField(all[all.length - 1], 'Tree');
  // A tree object is not reachable from any ref, so `git gc --prune=now` can
  // take it. That is a fortnight of grace by default and these live for
  // hours, but fall back rather than die on a base that has been collected.
  if (tree && git(['rev-parse', '--verify', '--quiet', tree]).status === 0) return tree;
  return 'HEAD';
}

// snapshotTree — write the working tree as a git tree object and return its
// sha, without touching the developer's index.
//
// The staging version of this made `git diff <tree>` work and the repository
// wrong; see baseIndex for what that cost.
function snapshotTree() {
  const idx = path.join(tmpDir(), 'leo-snap-' + process.pid + '-' + Math.random().toString(36).slice(2));
  const env = { GIT_INDEX_FILE: idx };
  try {
    git(['read-tree', 'HEAD'], { env });
    git(['add', '-A'], { env });
    const r = git(['write-tree'], { env });
    return r.status === 0 ? r.stdout.trim() : '';
  } finally {
    try { fs.unlinkSync(idx); } catch (e) { /* never created */ }
  }
}

module.exports = {
  records, recordCount, recordNextId, recordField, recordBase, snapshotTree,
};
