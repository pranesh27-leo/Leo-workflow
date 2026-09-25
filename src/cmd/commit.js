'use strict';
// desc: land every recorded cycle as one commit
// usage: leo commit ["<subject>"] [--no-check] [--list]
//
// The manifest goes in the message body, not in git notes or a side file, so
// that six months from now `git blame` -> `git show` tells you which task a
// line served and what breaks without it. No tooling, no AI, no lost context.
//
// Two shapes, and which one runs depends on whether any cycle has been
// recorded:
//
//   records waiting   every record becomes a section of one commit message,
//                     in the order the cycles happened. This is the normal
//                     shape: cycles end with `leo record`, and the change
//                     lands once, when the developer has seen all of it.
//   no records        the manifest goes straight into a commit, as it did
//                     before records existed.
//
// THIS COMMAND IS FOR HUMANS. It refuses to run without someone at a terminal
// to answer for the change. An agent that just wrote the code is the worst
// possible judge of whether the code is done -- it should run `leo record`
// and stop.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { info, dim, ok, warn, err, die, head_, LeoExit } = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const { isFile, readIfFile, tmpDir } = require('../lib/fsx');
const { git, changed, linesChanged } = require('../lib/repo');
const caps = require('../lib/caps');
const { records, recordCount, recordField, recordBase } = require('../lib/records');
const { sessionDesc } = require('../lib/session');
const { who } = require('../lib/who');
const { planGoal, manifestBody } = require('./record');
const checkCmd = require('./check');

// runCheck — `leo check`, in this process, with its own argument list.
//
// The sub-context is the point. Passing `ctx` straight through hands check
// the arguments of whatever called it, and `leo record "api: cap keys"`
// then dies with `unexpected argument: api: cap keys` from a command the
// developer never typed. The shell re-exec'd leo and got a fresh argv for
// free; in-process, the fresh argv has to be made deliberately.
function runCheck(ctx) {
  const sub = Object.create(ctx);
  sub.argv = [];
  try {
    return checkCmd.run(sub);
  } catch (e) {
    if (e && e.leoExitCode !== undefined) return e.leoExitCode;
    throw e;
  }
}


// One line from stdin, synchronously. The prompt has to block; there is no
// async here to await into. A pty and git-bash both append a carriage return.
function readLine() {
  const buf = Buffer.alloc(1);
  let out = '';
  try {
    while (fs.readSync(0, buf, 0, 1, null) === 1) {
      const ch = buf.toString('utf8');
      if (ch === '\n') break;
      out += ch;
    }
  } catch (e) {
    return '';
  }
  return out.replace(/\r/g, '');
}

function run(ctx) {
  needRepo(ctx);

  let subject = '', check = true, list = false;
  for (const a of ctx.argv) {
    if (a === '--no-check') check = false;
    else if (a === '--list') list = true;
    else if (a[0] === '-') die('unknown option: ' + a);
    else subject = subject ? subject + ' ' + a : a;
  }

  const all = records(ctx.records);
  const n = all.length;

  if (list) {
    if (n === 0) {
      info('no cycles recorded — the next commit is a plain one');
      return 0;
    }
    head_(n + ' cycle(s) recorded, none of them in git');
    for (const r of all) {
      info('  ' + path.basename(r, '.md') + '  ' + recordField(r, 'Subject'));
      dim('      ' + recordField(r, 'Date'));
    }
    info('');
    dim('  land them: leo commit "<subject>"');
    return 0;
  }

  // No TTY means nobody is here to say yes: an agent's shell, a pipe, a CI
  // job. After --list, which reads and changes nothing -- an agent showing
  // the developer what is waiting to land is exactly the behaviour this gate
  // wants.
  if (!process.stdin.isTTY && !process.env.LEO_YES) {
    err('leo commit needs a human at a terminal');
    info('');
    info('If you are an agent: do not commit. Record the cycle instead --');
    info('leo record "<subject>" -- and show them: leo commit');
    info('');
    info('If you are a human whose shell has no tty (a script, CI): LEO_YES=1 leo commit ...');
    throw new LeoExit(2);
  }

  // A subject is required when nothing is recorded, because there is nothing
  // else to write one from. With one record its subject is the obvious
  // default, and with several the developer is asked -- that is the whole
  // reason records exist, so the subject is written once, over the finished
  // change.
  if (!subject && n === 0) {
    die('usage: leo commit "<subject>"    (or: leo record "<subject>" to defer it)');
  }
  if (!subject && n === 1) {
    subject = recordField(all[0], 'Subject');
  }
  if (!subject) {
    if (process.env.LEO_YES) die(n + ' records — pass the subject: leo commit "<subject>"');
    head_(n + ' cycle(s) recorded');
    for (const r of all) info('  ' + recordField(r, 'Subject'));
    info('');
    info('One subject for all of it:');
    process.stderr.write('> ');
    subject = readLine();
    if (!subject) die('no subject — nothing committed');
  }

  if (check && runCheck(ctx) !== 0) {
    die('checks failed — fix them, or commit --no-check');
  }

  const adapters = ctx.adapters || caps.loadAdapters(ctx);
  ctx.adapters = adapters;

  const out = [];
  out.push(subject);
  out.push('');

  // Each recorded cycle keeps its own section: its subject, when it was
  // recorded, what it could see, and its own manifest. Merging the tables
  // into one would be shorter and would lose the only thing worth having --
  // which hunks were reviewed together, against which goal.
  for (const r of all) {
    out.push('--- ' + path.basename(r, '.md') + ': ' + recordField(r, 'Subject'));
    const rs = recordField(r, 'Session');
    if (rs) out.push('Session: ' + rs);
    out.push('Recorded: ' + recordField(r, 'Date'));
    out.push('');
    // Everything after the header block: the goal and the manifest table.
    const body = readIfFile(r) || '';
    const blank = body.indexOf('\n\n');
    out.push(blank === -1 ? '' : body.slice(blank + 2).replace(/\n$/, ''));
    out.push('');
  }

  // The plan's goal, so the commit states intent before mechanics. Records
  // carry their own, so this is for the un-recorded remainder.
  if (n === 0 && isFile(ctx.plan)) {
    const goal = planGoal(ctx.plan);
    if (goal) { out.push('Goal: ' + goal); out.push(''); }
  }

  if (isFile(ctx.manifest)) {
    out.push(manifestBody(ctx.manifest, 'HEAD'));
    out.push('');
  } else if (n === 0) {
    warn('no manifest — this commit records what changed but not why');
  }

  // What the agent could see when it wrote this. A change made with the prose
  // and context reducers on carries different risk from one made with full
  // diagnostic output, and six months from now the diff will not say which.
  const sess = sessionDesc(ctx, adapters);
  if (sess) out.push('Session: ' + sess);
  out.push('Assisted-by: ' + who());

  const msgFile = path.join(tmpDir(), 'leo-msg-' + process.pid + '-' + Date.now());
  fs.writeFileSync(msgFile, out.join('\n') + '\n');

  try {
    if (!process.env.LEO_YES) {
      head_('about to commit');
      info('  ' + subject);
      info('  ' + changed('HEAD').length + ' file(s), ' + linesChanged('HEAD') + ' lines');
      if (n > 0) info('  ' + n + ' recorded cycle(s), landing as one commit');
      // Work done after the last record belongs to no cycle: it was never
      // scanned, never manifested, and it is about to be committed alongside
      // work that was.
      if (n > 0 && !isFile(ctx.manifest)) {
        const loose = changed(recordBase(ctx.records)).length;
        if (loose > 0) warn('  ' + loose + ' file(s) changed since the last record, in no manifest');
      }
      if (isFile(ctx.manifest)) {
        const creep = (readIfFile(ctx.manifest) || '').split('\n')
          .filter((l) => /^\| *[0-9NEW]/.test(l))
          .filter((l) => (l.split('|')[4] || '').replace(/[ \t]/g, '') === '-').length;
        if (creep > 0) warn('  ' + creep + ' hunk(s) in this commit serve no task');
      }
      process.stderr.write('commit? [y/N] ');
      const answer = readLine();
      if (!/^y(es)?$/i.test(answer.trim())) {
        info('nothing committed');
        return 0;
      }
    }

    git(['add', '-A']);
    const c = spawnSync('git', ['commit', '-F', msgFile], {
      cwd: ctx.root, stdio: 'inherit', windowsHide: true,
    });
    if (c.status !== 0) die('git commit failed');
  } finally {
    try { fs.unlinkSync(msgFile); } catch (e) { /* already gone */ }
  }

  try { fs.unlinkSync(ctx.manifest); } catch (e) { /* never existed */ }
  // The records are spent: every one of them is inside the commit message
  // now, which is the only place they were ever going.
  try { fs.rmSync(ctx.records, { recursive: true, force: true }); } catch (e) { /* none */ }

  const short = git(['rev-parse', '--short', 'HEAD']).stdout.trim();
  ok('committed ' + short);
  if (n > 0) dim('  ' + n + ' recorded cycle(s) landed as one commit');
  dim('  read it back: git show --stat HEAD');

  // An agent session re-reads its whole context on every turn, so cost grows
  // with the square of the turn count: halving a session's length costs about
  // a third of its tokens, not half. A commit is the natural place to stop.
  dim('  now start a fresh session — .leo/tasks/ carries the state, and a long');
  dim('  session pays for every earlier turn on every later one');

  // --- cycle two ----------------------------------------------------------
  // The commit ends the dev cycle; it does not end the work. The change now
  // exists and nothing has read it except the developer who wrote it, which
  // is the one reviewer whose opinion is already spent.
  info('');
  head_('review it?');
  info('  The change is in, and unreviewed. Cycle two is a separate flow: it');
  info('  reads this commit -- goal, manifest and session are all in the message');
  info('  -- and it cannot edit the code, only find things about it.');
  info('');
  dim('  leo session --mode review');
  dim('  leo review ' + short);
  info('');
  dim('  It ends at: leo review --close');
  return 0;
}

module.exports = { run };
