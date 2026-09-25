'use strict';
// Cycle two.
//
// `.leo/reviews/<sha>.md` is one review of one commit that has already
// landed, and unlike the plan and the manifest it is *tracked*: those two end
// up inside the commit message they describe, and a review of an existing
// commit has nowhere to go but the repository. A record with no home is a
// record nobody reads.

const fs = require('fs');
const path = require('path');
const { readIfFile, isFile, isDir } = require('./fsx');
const { git } = require('./repo');
const { err, dim } = require('./ui');

// reviewCount <file> [state] [type] — findings, optionally filtered.
// The findings table is the only machine-readable part, and only two of its
// columns are: the state (column 3) and the type (column 7). Backticks are
// stripped because the table is written by hand and people quote cells.
function reviewCount(file, wantState, wantType) {
  const body = readIfFile(file);
  if (body === null) return 0;
  let n = 0;
  for (const line of body.split('\n')) {
    if (!/^\| *[0-9]/.test(line)) continue;
    const c = line.split('|');
    // awk's $3 and $7 are [2] and [6] here: $1 is the empty string before
    // the leading pipe. Off by one compares the wrong columns and every
    // "blocker/open" filter silently matches nothing.
    const s = (c[2] || '').replace(/[ \t`]/g, '');
    const t = (c[6] || '').replace(/[ \t`]/g, '');
    if (wantState && s !== wantState) continue;
    if (wantType && t !== wantType) continue;
    n++;
  }
  return n;
}

function headerField(file, name) {
  const body = readIfFile(file);
  if (body === null) return '';
  const re = new RegExp('^' + name + ': *(.*)$');
  for (const line of body.split('\n')) {
    const m = re.exec(line);
    if (m) return m[1];
  }
  return '';
}

const reviewVerdict = (f) => headerField(f, 'Verdict');
const reviewClosed = (f) => headerField(f, 'Closed');

// reviewSubject <file> — the reviewed commit's subject, off the title line.
// The separator is an em dash; skipping non-alphanumerics avoids naming a
// character that does not match reliably byte-wise.
function reviewSubject(file) {
  const body = readIfFile(file);
  if (body === null) return '';
  let line = body.split('\n')[0] || '';
  line = line.replace(/^# Review: */, '');
  const i = line.indexOf(' ');
  if (i !== -1) line = line.slice(i + 1);
  return line.replace(/^[^A-Za-z0-9]*/, '');
}

// reviewState <file> — closed once stamped; ready when the findings are all
// dispositioned and the verdict is real; open until then.
//
// "Ready" and "closed" are deliberately two things. They were one at first,
// derived from the same content, and the result was a review that could never
// be closed: the moment it satisfied the conditions it stopped looking like
// something waiting to be closed, and `--close` could no longer find it. The
// stamp is the difference between "nothing is outstanding" and "someone said
// so", which is the same difference the whole tool is built on.
function reviewState(file) {
  if (!isFile(file)) return 'missing';
  const closed = reviewClosed(file);
  if (closed && closed !== '-' && closed.indexOf('<') === -1) return 'closed';
  const verdict = reviewVerdict(file);
  if (!verdict || verdict.indexOf('<') !== -1) return 'open';
  if (reviewCount(file, 'blocker', 'open') > 0) return 'open';
  return 'ready';
}

function reviewList(reviewsDir) {
  if (!isDir(reviewsDir)) return [];
  return fs.readdirSync(reviewsDir)
    .filter((n) => n.endsWith('.md'))
    .sort()
    .map((n) => path.join(reviewsDir, n));
}

// reviewPick [rev] — the review to act on. Named, or the single open one.
// Returns null and has already explained why when it cannot decide.
function reviewPick(reviewsDir, rev) {
  if (rev) {
    let p = path.join(reviewsDir, rev + '.md');
    if (!isFile(p)) {
      const r = git(['rev-parse', '--short', rev]);
      if (r.status === 0) {
        const short = r.stdout.trim();
        if (short) p = path.join(reviewsDir, short + '.md');
      }
    }
    if (!isFile(p)) {
      err('no review for ' + rev + ' — open one: leo review ' + rev);
      return null;
    }
    return p;
  }
  const open = reviewList(reviewsDir).filter((f) => reviewState(f) !== 'closed');
  if (open.length === 0) {
    err('no open review — open one: leo review <rev>');
    return null;
  }
  if (open.length === 1) return open[0];
  err(open.length + ' reviews are open — name one: leo review --close <rev>');
  for (const f of open) dim('  ' + path.basename(f, '.md'));
  return null;
}

module.exports = {
  reviewCount, reviewVerdict, reviewClosed, reviewSubject,
  reviewState, reviewList, reviewPick,
};
