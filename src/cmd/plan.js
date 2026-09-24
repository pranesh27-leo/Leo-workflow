'use strict';
// desc: write or show the plan — what this change is allowed to be
// usage: leo plan                    show the plan in flight
//        leo plan "<name>"           start the NEXT plan and switch to it
//        leo plan "<name>" --force   replace the plan in flight instead
//        leo plan --list             every plan in this repository
//        leo plan --switch P1        work on an earlier plan again
//
// The plan is the yardstick. Without one, "did the AI do what I asked?" has
// no answer, and `leo check` has no budget to measure against.
//
// There is more than one of them, because a repository outlives a change. The
// developer finishes P1, comes back on Thursday wanting something else, and
// that something else is not an amendment to last week's plan -- it is P2,
// with its own goal, its own non-goals and its own budget. Saying so out loud
// is the difference between a second change and scope creep on the first.

const fs = require('fs');
const path = require('path');
const { say, info, dim, ok, warn, die, head_ } = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const { isFile, mkdirp, readIfFile } = require('../lib/fsx');
const p = require('../lib/plan');
const { now } = require('../lib/session');

function scaffold(name, id, first, second) {
  return `# Plan: ${name}

Id:      ${id || 'legacy'}
Created: ${now()}

## Goal
<One sentence: what changes, and why.>

## Non-goals
<What this change explicitly does not touch. This is what stops scope creep.>

## Wrong-change signal
<The one observation that would mean this is the wrong change entirely.>

## Tasks

| #  | Task          | Files   | Est LOC | Status  |
|----|---------------|---------|---------|---------|
| T${first} | <first task>  | <files> | <n>     | pending |
| T${second} | <second task> | <files> | <n>     | pending |

Status: pending -> in-progress -> done.
A task you are not doing yet goes to \`later\`: \`leo defer T${first} "why"\`.
Deferred tasks are skipped, not failed — the loop moves to the next one.
Task IDs must be T1, T2, ... — leo and the manifest match on that format, and
they never restart, so an id names one task in this repository forever.

Then give each row its own file and to-do: \`leo task T${first}\`.

## Later
<!-- \`leo defer\` writes here: one line per deferred task, with its reason.
     Nothing else should. \`leo resume\` takes lines back out. -->

## Budget
est: <n> LOC
`;
}

function countStatus(planFile, want) {
  return p.planRows(planFile).filter((r) => r.status === want).length;
}

function run(ctx) {
  needRepo(ctx);

  let name = '', force = false, list = false, switchTo = '';
  const argv = ctx.argv.slice();
  while (argv.length) {
    const a = argv.shift();
    if (a === '--force') force = true;
    else if (a === '--list') list = true;
    else if (a === '--switch') {
      if (!argv.length) die('--switch needs a plan id (leo plan --list)');
      switchTo = argv.shift();
    } else if (a[0] === '-') die('unknown option: ' + a);
    else name = a;
  }

  // --- list ---------------------------------------------------------------
  if (list) {
    head_('leo plan --list');
    const cur = ctx.planId;
    let n = 0;
    for (const id of p.plansList(ctx.plans)) {
      n++;
      const f = p.planPath(ctx.plans, id);
      const mark = id === cur ? '*' : ' ';
      const title = p.planName(f);
      const tasks = p.planTasks(f).length;
      const done = countStatus(f, 'done');
      const later = countStatus(f, 'later');
      info('  ' + mark + ' ' + id.padEnd(5) + ' ' + done + '/' + tasks + ' done' +
        (later > 0 ? ', ' + later + ' later' : '') + '  ' + title);
    }
    // The single-plan repository. It has no id of its own because every leo
    // before this one only ever had the one, and renaming it on sight would
    // move a file out from under whoever is mid-change in it.
    const legacy = path.join(ctx.leoDir, 'plan.md');
    if (isFile(legacy)) {
      n++;
      const mark = (cur === '' || cur === 'legacy') ? '*' : ' ';
      info('  ' + mark + ' ' + 'legacy'.padEnd(5) + ' ' + p.planName(legacy));
    }
    if (n === 0) {
      warn('no plans yet — start one: leo plan "<name>"');
      return 0;
    }
    process.stderr.write('\n');
    dim('  * is the plan in flight.  leo plan --switch P1  to move.');
    return 0;
  }

  // --- switch -------------------------------------------------------------
  if (switchTo) {
    if (switchTo === 'legacy') {
      if (!isFile(path.join(ctx.leoDir, 'plan.md'))) die('no legacy plan in this repository');
      try { fs.unlinkSync(ctx.current); } catch (e) { /* already gone */ }
      ctx.plan = path.join(ctx.leoDir, 'plan.md');
      ctx.tasks = path.join(ctx.leoDir, 'tasks');
      ctx.planId = '';
      ok('switched to the legacy plan (.leo/plan.md)');
      return 0;
    }
    if (!isFile(p.planPath(ctx.plans, switchTo))) {
      die('no such plan: ' + switchTo + '  (leo plan --list)');
    }
    mkdirp(ctx.leoDir);
    fs.writeFileSync(ctx.current, switchTo + '\n');
    ctx.planId = switchTo;
    ctx.plan = p.planPath(ctx.plans, switchTo);
    ctx.tasks = path.join(ctx.plans, switchTo, 'tasks');
    ok('switched to ' + switchTo);
    // The manifest belongs to a cycle, and a cycle belongs to one plan.
    // Carrying one across a switch would let hunks built for P1 be justified
    // by task ids from P2 -- the one dishonest move the manifest exists to
    // stop.
    if (isFile(ctx.manifest)) {
      warn('a manifest from the previous plan is still open — rm .leo/manifest.md && leo scan');
    }
    dim('  ' + p.planStatus(ctx.plan));
    return 0;
  }

  // --- show ---------------------------------------------------------------
  if (!name) {
    if (!isFile(ctx.plan)) {
      warn('no plan yet — start one: leo plan "<name>"');
      return 0;
    }
    // stdout, not stderr: the plan is leo's answer here, and `leo plan > f`
    // has to get the document rather than the commentary under it.
    process.stdout.write(readIfFile(ctx.plan));

    // Where the work stands, so picking up a half-finished change after a
    // day, a reboot or a lost session is one command rather than archaeology.
    const st = p.planStatus(ctx.plan);
    if (st) process.stderr.write('\n' + st + '\n');
    const later = p.planLater(ctx.plan);
    if (later.length) dim('  later: ' + later.join(' ') + '   (leo resume <id> to pick one back up)');
    return 0;
  }

  // --- create -------------------------------------------------------------
  // --force replaces the plan in flight; without it, a name always starts the
  // next plan. That is the reverse of the old behaviour, which refused, and
  // the reversal is the feature: "leo plan" with a new name now means "I want
  // something else", and wanting something else is the normal case.
  let target, id, first;
  if (force) {
    if (!isFile(ctx.plan)) die('nothing to replace — drop --force to start a plan');
    target = ctx.plan;
    id = ctx.planId;
    const existing = p.planTasks(ctx.plan)[0] || '';
    const n = parseInt(existing.replace(/^T/, ''), 10);
    first = (!isNaN(n) && n > 0) ? n : p.taskNextN(ctx.plans, path.join(ctx.leoDir, 'plan.md'));
  } else {
    id = p.planNextId(ctx.plans);
    target = p.planPath(ctx.plans, id);
    first = p.taskNextN(ctx.plans, path.join(ctx.leoDir, 'plan.md'));
  }
  const second = first + 1;

  mkdirp(path.dirname(target));
  fs.writeFileSync(target, scaffold(name, id, first, second));

  if (!force && id) {
    mkdirp(ctx.leoDir);
    fs.writeFileSync(ctx.current, id + '\n');
    ctx.planId = id;
    ctx.plan = target;
    ctx.tasks = path.join(ctx.plans, id, 'tasks');
  }

  const rel = target.startsWith(ctx.root + path.sep)
    ? target.slice(ctx.root.length + 1) : target;
  ok('plan created: ' + rel.split(path.sep).join('/') + (id ? '  (' + id + ')' : ''));
  dim('  tasks start at T' + first + ' — ids never restart, so T' + first + ' is T' + first + ' for good');
  dim('  Fill it in, then have the agent work one task at a time.');
  return 0;
}

module.exports = { run };
