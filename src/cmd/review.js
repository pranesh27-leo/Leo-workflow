'use strict';
// desc: open cycle two — a review of a commit that has already landed
// usage: leo review [<rev>]      open it, or show it
//        leo review --close      the gate of cycle two
//        leo review --list       every review, and its state
//
// Cycle two cannot edit the code. It reads a commit the dev cycle already
// made -- goal, manifest, non-goals and the decisions the grill settled are
// all in the message -- and files findings against it. A fix is a new dev
// cycle, not an edit from here.

const fs = require('fs');
const path = require('path');
const { info, dim, ok, warn, err, die, head_, LeoExit } = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const { isFile, isDir, readIfFile, mkdirp } = require('../lib/fsx');
const { git } = require('../lib/repo');
const rv = require('../lib/review');
const p = require('../lib/plan');
const { now } = require('../lib/session');

// Literal replacement; the same reason `leo task` avoids a regex. These
// values are commit subjects and diff excerpts, and a `$&` in one of them
// would silently corrupt the result.
function rep(str, from, to) {
  return str.split(from).join(to);
}

function uniq(list) {
  return Array.from(new Set(list));
}

// headerValues — every distinct value of a `Name: ` trailer in a commit
// message. A commit that landed several recorded cycles carries one per
// cycle, so taking only the first would brief the reviewer on part of a
// change and let them read all of it.
function headerValues(msg, name) {
  const re = new RegExp('^' + name + ': *(.*)$');
  const out = [];
  for (const line of msg.split('\n')) {
    const m = re.exec(line);
    if (m) out.push(m[1]);
  }
  return uniq(out);
}

// indentBlock — first line gets the label, the rest line up under it.
function labelled(label, values) {
  return values.map((v, i) => (i === 0 ? label + v : ' '.repeat(label.length) + v));
}

// planSection — the lines under a heading, skipping the template's
// placeholders, stopping at the next heading, table or budget line.
function planSection(planFile, heading) {
  const body = readIfFile(planFile);
  if (body === null) return [];
  const out = [];
  let inside = false;
  for (const line of body.split('\n')) {
    if (line.indexOf(heading) === 0) { inside = true; continue; }
    if (!inside) continue;
    if (/^## /.test(line) || /^\| /.test(line) || /^est:/.test(line)) break;
    if (line.trim() !== '' && line[0] !== '<') out.push('  ' + line);
  }
  return out;
}

// grillBody — what the grill settled, per task file. HTML comments are
// dropped: the template's instructions are not decisions.
function grillBody(taskFile) {
  const body = readIfFile(taskFile);
  if (body === null) return [];
  const out = [];
  let inGrill = false, inComment = false;
  for (const line of body.split('\n')) {
    if (/^## Grill/.test(line)) { inGrill = true; continue; }
    if (inGrill && /^## /.test(line)) inGrill = false;
    if (!inGrill) continue;
    if (/^<!--/.test(line)) inComment = true;
    if (inComment) {
      if (line.indexOf('-->') !== -1) inComment = false;
      continue;
    }
    if (line.trim() !== '' && line[0] !== '<') out.push('  ' + line);
  }
  return out;
}

// --------------------------------------------------------------- signals --
// Deterministic, and deliberately dumb. Each is a match whose only claim is
// "a human should glance here" -- most will be nothing, and clearing one
// costs a glance. Nothing here decides anything, so nothing here can be wrong
// in a way that matters; a signal leo does not raise is the failure mode, not
// a signal it raises for a line that turns out to be fine.
const SIGNALS = [
  ['Secrets — a literal assigned to a credential-shaped name',
    /(password|passwd|secret|token|api_?key|access_?key|private_?key|credential)[a-z_]*["' ]*[:=][ ]*["'][^"']{8,}/],
  ['Untrusted input reaching an interpreter',
    /(exec\(|eval\(|system\(|popen|subprocess|child_process|shell *= *true|innerhtml|dangerouslysetinnerhtml|document\.write|pickle\.load|yaml\.load|deserial|select .* from|insert into|delete from|\.raw\(|execute\()/],
  ['Authentication, authorisation and crypto',
    /(authenticat|authoriz|permission|is_?admin|\brole\b|session|jwt|oauth|bcrypt|hmac|cipher|encrypt|decrypt|md5|sha1|math\/rand|random\.)/],
  ['Errors that may be going nowhere',
    /(except:|except exception|rescue *(=>|$)|catch[^{]*\{ *\}|_ = err|\.unwrap\(\)|@ts-ignore|eslint-disable|# *nolint|\/\/ *nolint|type: *ignore)/],
  ['Left in by accident',
    /(todo|fixme|xxx|hack:|console\.log|debugger|binding\.pry|pdb\.set_trace|breakpoint\(\)|dbg!|fmt\.print)/],
];

const TEST_PAT = /(^|\/)(tests?|spec|__tests__)\/|(^|[._-])(test|spec)[._-]|_test\.|\.test\.|\.spec\.|(^|\/)test_/;
const DEP_PAT = /(^|\/)(package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|go\.mod|go\.sum|requirements[^/]*\.txt|pyproject\.toml|poetry\.lock|Pipfile|Cargo\.toml|Cargo\.lock|Gemfile|Gemfile\.lock|pom\.xml|build\.gradle[^/]*|composer\.json|composer\.lock|mix\.exs|pubspec\.yaml|[^/]*\.csproj)$/i;

// addedLines — every added line as {file, line, text}. Line numbers are the
// ones in the new file, tracked off the hunk headers, so a signal points at
// something you can actually open.
function addedLines(diff) {
  const out = [];
  let file = '', ln = 0;
  for (const line of diff.split('\n')) {
    if (line.indexOf('+++ b/') === 0) { file = line.slice(6); continue; }
    if (line.indexOf('--- ') === 0) continue;
    if (line.indexOf('@@') === 0) {
      const m = /^@@ [^+]*\+([0-9]+)/.exec(line);
      ln = m ? parseInt(m[1], 10) : 0;
      continue;
    }
    if (line[0] === '+' && file !== '') {
      out.push({ file, line: ln, text: line.slice(1) });
      ln++;
    }
  }
  return out;
}

function bigHunks(diff) {
  const out = [];
  let file = '', start = '', add = 0, del = 0, open = false;
  const flush = () => {
    if (open && add > 60) out.push('  ' + file + ':' + start + '  +' + add + '/-' + del);
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
  return out;
}

function run(ctx) {
  needRepo(ctx);

  let rev = '', close = false, list = false, force = false;
  for (const a of ctx.argv) {
    if (a === '--close') close = true;
    else if (a === '--list') list = true;
    else if (a === '--force') force = true;
    else if (a[0] === '-') die('unknown option: ' + a);
    else { if (rev) die('unexpected argument: ' + a); rev = a; }
  }

  mkdirp(ctx.reviews);

  // --- list ---------------------------------------------------------------
  if (list) {
    head_('leo review');
    const all = rv.reviewList(ctx.reviews);
    for (const f of all) {
      info('  ' + path.basename(f, '.md').padEnd(10) + ' ' +
        rv.reviewState(f).padEnd(9) + ' ' +
        (rv.reviewCount(f, 'blocker') + 'b/' + rv.reviewCount(f) + 'f').padEnd(5) + ' ' +
        rv.reviewSubject(f));
    }
    if (all.length === 0) dim('  no reviews yet — leo review <rev>');
    return 0;
  }

  // --- close --------------------------------------------------------------
  // The gate of cycle two, and the only thing in it that refuses. It checks
  // the vocabulary (so the columns stay machine-readable), that every finding
  // has been dispositioned, and that the verdict is a real sentence rather
  // than the placeholder the template shipped with. It never decides whether
  // the code is good -- that is written in the file by whoever read it.
  if (close) {
    const f = rv.reviewPick(ctx.reviews, rev);
    if (!f) throw new LeoExit(1);
    const id = path.basename(f, '.md');
    let bad = false;

    head_('closing review ' + id);

    // 1. vocabulary. A status leo cannot read is a finding nobody
    // dispositioned, and it must not pass by being unparseable.
    const problems = [];
    for (const line of (readIfFile(f) || '').split('\n')) {
      if (!/^\| *[0-9]/.test(line)) continue;
      const c = line.split('|');
      const sev = (c[2] || '').replace(/[ \t`]/g, '');
      const st = (c[6] || '').replace(/[ \t`]/g, '');
      const n = (c[1] || '').replace(/[ \t]/g, '');
      if (sev !== 'blocker' && sev !== 'improvement' && sev !== 'nit') {
        problems.push('  row ' + n + ': severity "' + sev + '" is not blocker/improvement/nit');
      } else if (st !== 'open' && st !== 'fixed' && st !== 'waived') {
        problems.push('  row ' + n + ': status "' + st + '" is not open/fixed/waived');
      }
    }
    if (problems.length) {
      err('the findings table does not read');
      for (const l of problems) info(l);
      bad = true;
    }

    // 2. open blockers. The one thing that holds a review open.
    const openBlockers = rv.reviewCount(f, 'blocker', 'open');
    if (openBlockers > 0) {
      err(openBlockers + ' blocker(s) still open — fix them in a new dev cycle, or waive them');
      for (const line of (readIfFile(f) || '').split('\n')) {
        if (!/^\| *[0-9]/.test(line)) continue;
        const c = line.split('|');
        const sev = (c[2] || '').replace(/[ \t`]/g, '');
        const st = (c[6] || '').replace(/[ \t`]/g, '');
        if (sev === 'blocker' && st === 'open') {
          info('  ' + (c[3] || '').trim() + '  ' + (c[4] || '').trim());
        }
      }
      dim('  a fix is a dev cycle, not an edit: leo plan "fix: ' + id + ' review"');
      dim("  waiving one is the developer's call, and it stays in the file");
      bad = true;
    }

    // 3. the verdict. Same test as the manifest's Tests: line -- a conclusion
    // nobody typed is not a conclusion, and the template's placeholder is how
    // you tell.
    const verdict = rv.reviewVerdict(f);
    if (!verdict || verdict.indexOf('<') !== -1) {
      err('the review states no verdict — say ship or fix-first, and why');
      bad = true;
    }

    if (bad) die('review ' + id + ' stays open');

    // The stamp, written from something that actually happened. Until it is
    // here the review is merely ready; a review nobody signed is not a review
    // that closed.
    const body = readIfFile(f) || '';
    if (/^Closed:/m.test(body)) {
      fs.writeFileSync(f, body.split('\n')
        .map((l) => (/^Closed:/.test(l) ? 'Closed: ' + now() : l)).join('\n'));
    } else {
      fs.appendFileSync(f, 'Closed: ' + now() + '\n');
    }

    const nb = rv.reviewCount(f, 'blocker');
    const nf = rv.reviewCount(f);
    const waived = rv.reviewCount(f, 'blocker', 'waived');
    ok('review ' + id + ' closes — ' + nf + ' finding(s), ' + nb + ' blocker(s), ' + waived + ' waived');
    if (waived > 0) warn(waived + ' waived blocker(s) — they stay in the file, and in the log');

    // Everything still open that is not a blocker is a backlog, not a
    // failure.
    const rest = rv.reviewCount(f, 'improvement', 'open') + rv.reviewCount(f, 'nit', 'open');
    if (rest > 0) dim('  ' + rest + ' open improvement(s)/nit(s) — a dev cycle when you want them, not now');

    info('');
    info('The review is a record of a commit that already exists, so unlike the');
    info('plan and the manifest it has nowhere to live but the repository:');
    const relf = f.startsWith(ctx.root + path.sep) ? f.slice(ctx.root.length + 1) : f;
    dim('  git add ' + relf.split(path.sep).join('/') + ' && git commit -m "review: ' + id +
      ' — ' + verdict.split(' ')[0] + ', ' + nf + ' finding(s)"');
    return 0;
  }

  // --- open, or show ------------------------------------------------------
  rev = rev || 'HEAD';
  const isRange = rev.indexOf('..') !== -1;
  let tip = rev;
  if (isRange) {
    tip = rev.slice(rev.lastIndexOf('..') + 2) || 'HEAD';
  }
  if (git(['rev-parse', '--verify', '--quiet', tip + '^{commit}']).status !== 0) {
    die("'" + rev + "' is not a commit this repository has");
  }
  const sha = git(['rev-parse', '--short', tip]).stdout.trim();
  const f = path.join(ctx.reviews, sha + '.md');

  if (isFile(f) && !force) {
    process.stdout.write(readIfFile(f));
    info('');
    dim('  ' + rv.reviewState(f) + ' — leo review --close when the findings are dispositioned');
    dim('  leo review ' + rev + ' --force replaces it, and loses what is written above');
    return 0;
  }

  // The diff under review. A range is diffed end to end; a single commit is
  // shown as itself, so a review of an old commit reads that commit and not
  // everything since. -U0 for both: hunks, not context, exactly as `leo scan`
  // takes them.
  const diff = isRange
    ? git(['diff', '-U0', rev]).stdout
    : git(['show', '-U0', '--format=', rev]).stdout;

  const msg = git(['show', '-s', '--format=%B', tip]).stdout.replace(/\n$/, '');
  const subject = msg.split('\n')[0] || '';

  // ------------------------------------------------------------- context --
  // What the dev cycle recorded, quoted rather than summarised. Every part of
  // this is already written down somewhere; the value is having it in one
  // place before the diff is read, not in having it restated.
  const ctxOut = [];
  ctxOut.push('Commit:  ' + sha + '  (' +
    git(['show', '-s', '--format=%an', tip]).stdout.trim() + ', ' +
    git(['show', '-s', '--format=%ad', '--date=short', tip]).stdout.trim() + ')');
  if (isRange) ctxOut.push('Range:   ' + rev);
  ctxOut.push('Subject: ' + subject);

  const goals = headerValues(msg, 'Goal');
  if (goals.length) ctxOut.push(...labelled('Goal:    ', goals));
  const sessions = headerValues(msg, 'Session');
  if (sessions.length) ctxOut.push(...labelled('Session: ', sessions));
  const by = headerValues(msg, 'Assisted-by');
  if (by.length) ctxOut.push('Written: ' + by[0]);

  // The manifest, straight out of the commit message. This is the dev
  // cycle's own answer to "why does this hunk exist", and the review's job is
  // to test it against the code -- not to write it again.
  //
  // One table, however many cycles were recorded into this commit: the column
  // header repeats once per section, and a reviewer does not need to be told
  // what the columns are three times. Every row is kept.
  const manLines = [];
  let sawHeader = false;
  for (const line of msg.split('\n')) {
    if (line.indexOf('| ') !== 0) continue;
    if (/^\| *# *\| *Hunk/.test(line)) {
      if (sawHeader) continue;
      sawHeader = true;
    }
    manLines.push(line);
  }
  if (manLines.length) {
    ctxOut.push('');
    ctxOut.push('### The manifest this commit was made with');
    ctxOut.push('');
    ctxOut.push(...manLines);
    const budget = uniq(msg.split('\n').filter((l) => l.indexOf('Budget:') === 0));
    const tests = uniq(msg.split('\n').filter((l) => l.indexOf('Tests:') === 0));
    if (budget.length) { ctxOut.push(''); ctxOut.push(...budget); }
    if (tests.length) ctxOut.push(...tests);
  } else {
    ctxOut.push('');
    ctxOut.push('### No manifest in this commit message');
    ctxOut.push('');
    ctxOut.push('The change was committed without one, so nothing here says why any');
    ctxOut.push('hunk exists. Read the diff with that in mind, and say so in the');
    ctxOut.push('verdict -- it is a finding about the change, not about the review.');
  }

  // The plan is working state and survives on disk after the commit. It may
  // well be the next change's plan by the time anyone reads this, so it is
  // labelled rather than presented as fact.
  if (isFile(ctx.plan)) {
    const ng = planSection(ctx.plan, '## Non-goals');
    const ws = planSection(ctx.plan, '## Wrong-change');
    if (ng.length || ws.length) {
      ctxOut.push('');
      ctxOut.push('### From .leo/plan.md — "' + p.planName(ctx.plan) + '"');
      ctxOut.push('');
      ctxOut.push('(Still on disk. Check it is this change before you trust it.)');
      if (ng.length) {
        ctxOut.push('');
        ctxOut.push('Non-goals — a hunk that serves one of these is a finding:');
        ctxOut.push('');
        ctxOut.push(...ng);
      }
      if (ws.length) {
        ctxOut.push('');
        ctxOut.push('Wrong-change signal:');
        ctxOut.push('');
        ctxOut.push(...ws);
      }
    }
  }

  // The grill: the decisions behind the code, which the diff cannot show.
  // This is the part of the dev cycle a reviewer most often has to guess at,
  // and the one place leo already has it written down.
  const grill = [];
  if (isDir(ctx.tasks)) {
    for (const tf of fs.readdirSync(ctx.tasks).filter((x) => x.endsWith('.md')).sort()) {
      const lines = grillBody(path.join(ctx.tasks, tf));
      if (lines.length) {
        grill.push(tf.slice(0, -3) + ':');
        grill.push(...lines);
      }
    }
  }
  if (grill.length) {
    ctxOut.push('');
    ctxOut.push('### What the grill settled — from .leo/tasks/');
    ctxOut.push('');
    ctxOut.push('Decisions the code cannot record. A finding that contradicts one of');
    ctxOut.push('these is really a finding about the decision, so say that.');
    ctxOut.push('');
    ctxOut.push(...grill);
  }

  // ------------------------------------------------------------- signals --
  const added = addedLines(diff);
  const sigOut = [];
  for (const [title, pat] of SIGNALS) {
    const hits = [];
    for (const a of added) {
      // The path is excluded from the match on purpose: half these patterns
      // are ordinary words in a filename, and `auth/token.go` would otherwise
      // light up every signal it has a word for.
      const t = a.text.replace(/^[ \t]+/, '');
      if (pat.test(t.toLowerCase())) {
        hits.push('  ' + a.file + ':' + a.line + '  ' + t.slice(0, 100));
      }
    }
    if (!hits.length) continue;
    const shown = hits.slice(0, 10);
    if (hits.length > 10) shown.push('  ... and ' + (hits.length - 10) + ' more');
    sigOut.push('### ' + title, '', '```', ...shown, '```', '');
  }

  const files = uniq(diff.split('\n')
    .filter((l) => l.indexOf('+++ b/') === 0)
    .map((l) => l.slice(6))).sort();

  const deps = files.filter((x) => DEP_PAT.test(x));
  if (deps.length) {
    sigOut.push('### Dependency manifests changed', '', '```',
      ...deps.map((d) => '  ' + d), '```', '');
  }

  // Tests, as a count rather than a judgement. "No test file changed" is not
  // automatically wrong -- a refactor covered by existing tests is the normal
  // case -- but it is always worth one sentence in the review.
  const nt = files.filter((x) => TEST_PAT.test(x)).length;
  const ns = files.length - nt;
  sigOut.push('### Tests', '',
    ns + ' source file(s) changed, ' + nt + ' test file(s) changed.');
  if (nt === 0 && ns > 0) {
    sigOut.push('', 'No test file changed. Ask the standards question: is there a test',
      'that fails without this change? If not, say so as a finding.');
  }
  sigOut.push('');

  const big = bigHunks(diff);
  if (big.length) {
    sigOut.push('### Hunks over 60 added lines', '', '```', ...big, '```', '');
  }

  // The dev cycle's own admission, carried forward. A hunk that served no
  // task went in anyway; whether that was fine is a review question.
  const creep = msg.split('\n')
    .filter((l) => /^\| *[0-9NEW]/.test(l))
    .filter((l) => (l.split('|')[4] || '').replace(/[ \t]/g, '') === '-').length;
  if (creep > 0) {
    sigOut.push('### ' + creep + ' hunk(s) in this commit served no task', '',
      'The manifest says so itself. They were committed anyway, which was',
      "the developer's call -- but unrequested code is code nobody framed,",
      'and it is the first place to look for a defect.', '');
  }

  let signals = sigOut.join('\n').replace(/\n$/, '');
  if (signals.trim() === '') {
    signals = 'Nothing flagged. That is not a clean bill of health — it\n' +
      'means no grep matched, and every grep here is shallow by design.';
  }

  // --------------------------------------------------------------- write --
  if (!ctx.assets.tmplHas('review.md')) die('missing template: review.md');
  const context = ctxOut.join('\n');
  const out = ctx.assets.tmplRead('review.md').split('\n').map((line) => {
    let l = rep(line, '<REV>', sha);
    l = rep(l, '<SUBJECT>', subject);
    if (l === '<CONTEXT>') return context;
    if (l === '<SIGNALS>') return signals;
    return l;
  }).join('\n');
  fs.writeFileSync(f, out);

  const relf = f.startsWith(ctx.root + path.sep) ? f.slice(ctx.root.length + 1) : f;
  ok('opened ' + relf.split(path.sep).join('/') + ' — ' + sha + ', ' + files.length + ' file(s)');
  info('');
  info('Read, in this order:');
  dim('  1. the "What was asked for" section — what the dev cycle recorded');
  dim('  2. CODE_REVIEW.md — what a finding here has to clear');
  dim('  3. ' + (isRange ? 'git diff ' + rev : 'git show ' + sha) + ' — the code, against both');
  info('');
  dim('Then fill the findings table, write the verdict, and: leo review --close');
  dim('You cannot fix anything from here. A fix is a new dev cycle.');
  return 0;
}

module.exports = { run };
