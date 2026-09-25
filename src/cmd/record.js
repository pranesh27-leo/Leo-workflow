'use strict';
// desc: record this cycle's commit message without committing
// usage: leo record "<subject>" [--no-check]
//
// The end of a cycle, without the end of the change. leo checks the work,
// files the message this cycle would have committed -- subject, goal,
// manifest, session -- into .leo/commits/, clears the manifest, and stops.
// Nothing lands.
//
// `leo commit` then folds every record into one commit, when the developer
// has seen the whole change and not before. That is the point: "is this cycle
// finished" and "is this change done" are different questions, and committing
// made you answer the second one every time you meant the first.
//
// Unlike `leo commit`, an agent may run this. It writes no history and
// touches neither the index nor the working tree -- undoing it is deleting
// one file.

const fs = require('fs');
const path = require('path');
const { info, dim, ok, warn, die } = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const { isFile, readIfFile, mkdirp } = require('../lib/fsx');
const { changed } = require('../lib/repo');
const p = require('../lib/plan');
const caps = require('../lib/caps');
const { recordBase, recordNextId, recordCount, snapshotTree } = require('../lib/records');
const { sessionDesc, now } = require('../lib/session');
const { who } = require('../lib/who');
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


// planGoal — the first real line under "## Goal", so a record states intent
// before it states mechanics. Placeholder lines (the template's angle
// brackets) are skipped: a goal nobody wrote is worse than no goal line.
function planGoal(planFile) {
  const body = readIfFile(planFile);
  if (body === null) return '';
  let inGoal = false;
  for (const line of body.split('\n')) {
    if (/^## Goal/.test(line)) { inGoal = true; continue; }
    if (!inGoal) continue;
    if (/^##/.test(line)) break;
    if (line.trim() !== '' && line[0] !== '<') return line;
  }
  return '';
}

// manifestBody — the manifest with its "# Manifest" title dropped, its
// Base: line dropped when that base is the previous record's tree, and any
// leading blank lines trimmed.
//
// The tree sha is worth nothing to whoever reads this commit years from now
// -- the object is unreachable and will have been collected -- while a real
// base (`leo scan main`) is worth keeping.
function manifestBody(manifestFile, base) {
  let lines = (readIfFile(manifestFile) || '').split('\n');
  if (lines[0] === '# Manifest') lines = lines.slice(1);
  lines = lines.filter((l) => l !== 'Base: ' + base);
  while (lines.length && lines[0].trim() === '') lines.shift();
  return lines.join('\n');
}

function run(ctx) {
  needRepo(ctx);

  let subject = '', check = true;
  for (const a of ctx.argv) {
    if (a === '--no-check') check = false;
    else if (a[0] === '-') die('unknown option: ' + a);
    else subject = subject ? subject + ' ' + a : a;
  }
  if (!subject) die('usage: leo record "<subject>"');

  // The same gate the commit used to carry. A record that was never checked
  // is a record that will be checked at landing time instead, in a batch,
  // against a manifest that has already been consumed -- which is to say
  // never.
  //
  // Called in-process rather than by spawning leo again: the shell had to
  // re-exec itself, and that cost a whole second interpreter start plus a
  // reload of every adapter on the one command that already does the most
  // work.
  if (check && runCheck(ctx) !== 0) {
    die('checks failed — fix them, or record --no-check');
  }

  const base = recordBase(ctx.records);
  if (changed(base).length === 0) {
    die('nothing has changed since the last record — nothing to record');
  }

  mkdirp(ctx.records);
  const id = recordNextId(ctx.records);
  const file = path.join(ctx.records, id + '.md');

  // The tree this cycle leaves behind, so the next `leo scan` enumerates only
  // the next cycle's hunks. Taken before the file is written: .leo/commits/
  // is gitignored, so the record cannot appear in its own snapshot either
  // way, but the ordering is what makes that true rather than incidental.
  const tree = snapshotTree();

  const adapters = ctx.adapters || caps.loadAdapters(ctx);
  ctx.adapters = adapters;

  const out = [];
  out.push('Subject: ' + subject);
  out.push('Date: ' + now());
  out.push('Tree: ' + tree);
  const sess = sessionDesc(ctx, adapters);
  if (sess) out.push('Session: ' + sess);
  out.push('Assisted-by: ' + who());
  out.push('');

  // Which plan this cycle belongs to. A repository has several, task ids are
  // unique across all of them, and a record that named a task without naming
  // its plan would be readable today and ambiguous in a year.
  if (ctx.planId) out.push('Plan: ' + ctx.planId);

  const goal = planGoal(ctx.plan);
  if (goal) { out.push('Goal: ' + goal); out.push(''); }

  // Which declared tools actually built these hunks. It sits next to the
  // manifest for the same reason the manifest sits in the commit message: the
  // answer is only meaningful beside the code it is an answer about.
  const tools = caps.usedList(ctx).join(' ');
  if (tools) { out.push('Tools: ' + tools); out.push(''); }

  // What this change deliberately did not attempt. A reviewer six months out
  // needs to tell "we decided not to yet" from "nobody thought of it", and
  // the only moment that difference is cheap to record is now.
  const later = p.planLater(ctx.plan);
  if (later.length) {
    out.push('Later:');
    for (const t of later) {
      out.push('  ' + t + ' ' + p.planTaskName(ctx.plan, t) + ' — ' + p.planLaterWhy(ctx.plan, t));
    }
    out.push('');
  }

  if (isFile(ctx.manifest)) {
    out.push(manifestBody(ctx.manifest, base));
  } else {
    warn('no manifest — this record says what changed but not why');
  }

  fs.writeFileSync(file, out.join('\n'));

  // The manifest is spent: it is inside the record now, and leaving it would
  // make the next `leo scan` refuse to start. The tool ledger goes with it --
  // it answers "what built these hunks", and the next cycle's hunks are
  // different hunks.
  try { fs.unlinkSync(ctx.manifest); } catch (e) { /* never existed */ }
  try { fs.unlinkSync(ctx.used); } catch (e) { /* never existed */ }

  const n = recordCount(ctx.records);
  const rel = file.startsWith(ctx.root + path.sep)
    ? file.slice(ctx.root.length + 1) : file;
  ok('recorded ' + id + ' — nothing committed');
  dim('  ' + subject);
  dim('  ' + rel.split(path.sep).join('/'));
  info('');
  info(n + ' cycle(s) recorded. Nothing is in git yet.');
  dim('  read them back: leo commit --list');
  dim('  land them all:  leo commit          <- the developer\'s, and one commit');

  // A session re-reads its whole context every turn, so cost grows with the
  // square of the turn count. A finished cycle is the natural place to stop
  // whether or not it landed.
  info('');
  dim('  now start a fresh session — .leo/tasks/ and .leo/commits/ carry the');
  dim('  state, and a long session pays for every earlier turn on every later one');
  return 0;
}

module.exports = { run, planGoal, manifestBody };
