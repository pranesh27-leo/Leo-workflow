'use strict';
// desc: take a task or subtask back out of later work
// usage: leo resume <T3|T3.2>

const fs = require('fs');
const { dim, ok, warn, die } = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const { isFile, readIfFile } = require('../lib/fsx');
const p = require('../lib/plan');
const { nextStep } = require('../lib/session');

function run(ctx) {
  needRepo(ctx);
  if (!isFile(ctx.plan)) die('no plan — nothing to resume');

  const id = ctx.argv[0] || '';
  if (!id) die('usage: leo resume <T3|T3.2>');
  if (!/^T[0-9]/.test(id)) die('ids are T1, T2, T1.2, … — got: ' + id);

  // --- a subtask ----------------------------------------------------------
  if (id.indexOf('.') !== -1) {
    const parent = id.split('.')[0];
    const pf = p.taskFile(ctx.tasks, parent);
    if (!isFile(pf)) die(parent + ' has no file');
    if (p.subtaskState(ctx.tasks, parent, id) !== 'later') {
      die(id + ' is not later work — nothing to resume');
    }

    // Drop the Status line, and only inside this subtask's section. A global
    // delete would resume every deferred subtask in the file at once.
    const out = [];
    let here = false;
    for (const line of (readIfFile(pf) || '').split('\n')) {
      const f = line.split(/\s+/);
      if (f[0] === '##') here = (f[1] === id);
      if (here && /^Status: *later/.test(line)) continue;
      out.push(line);
    }
    fs.writeFileSync(pf, out.join('\n'));

    ok(id + ' is back in the work');
    if (p.taskUngrilled(ctx.tasks, parent) > 0) {
      warn(id + ' is ungrilled — grill it before you build it');
      dim('  it was never grilled: a deferred subtask is not grilled on purpose.');
      dim('  .leo/skills/grilling/SKILL.md');
    }
    return 0;
  }

  // --- a task -------------------------------------------------------------
  if (!p.planHasTask(ctx.plan, id)) {
    const own = p.taskOwner(ctx.plans, id);
    if (own) die(id + ' belongs to ' + own + ' — leo plan --switch ' + own);
    die(id + ' is not a task in this plan');
  }
  if (p.planTaskStatus(ctx.plan, id) !== 'later') {
    die(id + ' is not later work — nothing to resume');
  }

  const out = [];
  let inLater = false;
  for (const line of (readIfFile(ctx.plan) || '').split('\n')) {
    if (/^\| *T[0-9]/.test(line)) {
      const f = line.split('|');
      if ((f[1] || '').replace(/\s/g, '') === id) {
        let w = (f[5] || '').length - 2;
        if (w < 1) w = 1;
        f[5] = ' ' + 'pending'.padEnd(w) + ' ';
        out.push(f.slice(1, f.length - 1).map((c) => '|' + c).join('') + '|');
        continue;
      }
    }
    // The reason goes with the deferral. Leaving it behind would make the
    // plan claim a task is still parked while its status says otherwise, and
    // the two would disagree for as long as the plan lives.
    if (/^- /.test(line) && inLater) {
      const rowId = line.replace(/^- /, '').split(' ')[0];
      if (rowId === id) continue;
    }
    if (/^## Later/.test(line)) inLater = true;
    else if (/^## /.test(line)) inLater = false;
    out.push(line);
  }
  fs.writeFileSync(ctx.plan, out.join('\n'));

  ok(id + ' is back in the work — pending');
  if (p.taskCurrent(ctx.plan) === id) dim('  it is the task in flight again: ' + nextStep(ctx));
  return 0;
}

module.exports = { run };
