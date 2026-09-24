'use strict';
// desc: park a task or subtask as later work, with the reason
// usage: leo defer <T3|T3.2> "<why>"
//        leo defer --list
//
// The reason is not optional. A status cell saying "later" is a decision; the
// reason is the only thing that makes it reviewable. Without one, a deferral
// is indistinguishable from a task somebody forgot, and six weeks later
// nobody can tell which it was.

const fs = require('fs');
const { info, dim, ok, die, head_ } = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const { isFile, readIfFile } = require('../lib/fsx');
const p = require('../lib/plan');
const { now } = require('../lib/session');

function run(ctx) {
  needRepo(ctx);

  let id = '', why = '', list = false;
  const argv = ctx.argv.slice();
  while (argv.length) {
    const a = argv.shift();
    if (a === '--list') list = true;
    else if (a[0] === '-') die('unknown option: ' + a);
    else if (!id) id = a;
    else why = why ? why + ' ' + a : a;
  }

  if (!isFile(ctx.plan)) die('no plan — nothing to defer (leo plan "<name>")');

  // --- list ---------------------------------------------------------------
  if (list) {
    head_('later work');
    let n = 0;
    for (const t of p.planLater(ctx.plan)) {
      n++;
      info('  ' + t.padEnd(6) + ' ' + p.planTaskName(ctx.plan, t).padEnd(28) + ' ' +
        p.planLaterWhy(ctx.plan, t));
    }
    // Subtasks, which live in their parent's file rather than in the table.
    for (const t of p.planTasks(ctx.plan)) {
      for (const s of p.taskLaterSubs(ctx.tasks, t)) {
        n++;
        info('  ' + s.padEnd(6) + ' (subtask of ' + t + ')');
      }
    }
    if (n === 0) dim('  nothing deferred');
    process.stderr.write('\n');
    dim('  pick one back up: leo resume <id>');
    return 0;
  }

  if (!id) die('usage: leo defer <T3|T3.2> "<why>"');
  if (!why) die('a deferral needs a reason — leo defer ' + id + ' "<why>"');
  if (!/^T[0-9]/.test(id)) die('ids are T1, T2, T1.2, … — got: ' + id);

  const when = now();

  // --- a subtask ----------------------------------------------------------
  // A dot in the id means a heading inside a task file, not a row in the plan.
  if (id.indexOf('.') !== -1) {
    const parent = id.split('.')[0];
    const pf = p.taskFile(ctx.tasks, parent);
    if (!isFile(pf)) die(parent + ' has no file — nothing to defer inside it');
    if (p.subtaskIds(ctx.tasks, parent).indexOf(id) === -1) {
      die(pf + ' has no subtask ' + id + '  (leo task ' + parent + ')');
    }
    if (p.subtaskState(ctx.tasks, parent, id) === 'later') die(id + ' is already later work');

    // The marker goes directly under the heading, before the ungrilled
    // comment, because that is the order taskUngrilled reads them in: a
    // Status line arriving after the marker would not cover it, and the check
    // would go on demanding a grill for work that is not happening.
    const out = [];
    for (const line of (readIfFile(pf) || '').split('\n')) {
      out.push(line);
      const f = line.split(/\s+/);
      if (f[0] === '##' && f[1] === id) {
        out.push('Status: later — ' + why + '  (' + when + ')');
      }
    }
    fs.writeFileSync(pf, out.join('\n'));

    ok(id + ' is later work');
    dim('  ' + why);
    dim('  it is skipped by the grill check and by the to-do — leo resume ' + id);
    return 0;
  }

  // --- a task -------------------------------------------------------------
  if (!p.planHasTask(ctx.plan, id)) {
    const own = p.taskOwner(ctx.plans, id);
    if (own) die(id + ' belongs to ' + own + ', not the plan in flight — leo plan --switch ' + own);
    die(id + ' is not a task in this plan  (leo task)');
  }

  const st = p.planTaskStatus(ctx.plan, id);
  if (st === 'later') die(id + ' is already later work');
  if (st === 'done') die(id + ' is already done — deferring it would undo a fact');

  // Two edits to one file, in one pass: the status cell, and a line under
  // "## Later" carrying the reason. The cell is what every other command
  // reads; the line is the only place the why can live, and a status with no
  // why is the thing this command exists to prevent.
  //
  // The section is created when the plan predates it, so a plan written by an
  // older leo does not silently drop the reason on the floor.
  const lines = (readIfFile(ctx.plan) || '').split('\n');
  const out = [];
  let seenLater = false;
  for (const line of lines) {
    if (/^\| *T[0-9]/.test(line)) {
      const f = line.split('|');
      const rowId = (f[1] || '').replace(/\s/g, '');
      if (rowId === id) {
        // Rewrite the status cell only, keeping its width so the table still
        // reads as a table. Replacing across the whole line would hit the
        // task name if it happened to contain the old status word.
        let w = (f[5] || '').length - 2;
        if (w < 1) w = 1;
        f[5] = ' ' + 'later'.padEnd(w) + ' ';
        out.push(f.slice(1, f.length - 1).map((c) => '|' + c).join('') + '|');
        continue;
      }
    }
    if (/^## Later/.test(line)) {
      seenLater = true;
      out.push(line);
      out.push('- ' + id + ' — ' + why + '  (' + when + ')');
      continue;
    }
    out.push(line);
  }
  if (!seenLater) {
    out.push('');
    out.push('## Later');
    out.push('- ' + id + ' — ' + why + '  (' + when + ')');
  }
  fs.writeFileSync(ctx.plan, out.join('\n'));

  ok(id + ' is later work');
  dim('  ' + why);
  const next = p.taskCurrent(ctx.plan);
  if (next) dim('  next: ' + next + ' ' + p.planTaskName(ctx.plan, next));
  else dim('  nothing left in this plan but later work — leo plan "<next change>"');
  dim('  pick it back up: leo resume ' + id);
  return 0;
}

module.exports = { run };
