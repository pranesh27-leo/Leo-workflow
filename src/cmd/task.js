'use strict';
// desc: give a task its own file, to-do and grill — or show it
// usage: leo task                 list the plan's tasks
//        leo task T1              create it, or show it
//        leo task T1 --force      rewrite it from the template
//        leo task T1 --sub "<name>"  add a subtask inside T1's file

const fs = require('fs');
const path = require('path');
const { info, dim, ok, warn, die, head_ } = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const { isFile, mkdirp, readIfFile } = require('../lib/fsx');
const p = require('../lib/plan');
const caps = require('../lib/caps');

// Literal replacement, character by character.
//
// The shell used awk with an index/substr loop rather than gsub, and the
// reason survives the port: a task name is free text from the plan. JS
// String.replace treats `$&` and friends in the REPLACEMENT as references, so
// a task named "rate limit $& retry" would come out mangled the same way
// awk's gsub mangled "&". split/join has no metacharacters at any level.
function rep(str, from, to) {
  return str.split(from).join(to);
}

function run(ctx) {
  needRepo(ctx);

  let id = '', force = false, sub = '';
  const argv = ctx.argv.slice();
  while (argv.length) {
    const a = argv.shift();
    if (a === '--force') force = true;
    else if (a === '--sub') {
      if (!argv.length) die('--sub needs a name');
      sub = argv.shift();
    } else if (a[0] === '-') die('unknown option: ' + a);
    else id = a;
  }

  // --- list ---------------------------------------------------------------
  if (!id) {
    if (!isFile(ctx.plan)) {
      warn('no plan yet — start one: leo plan "<name>"');
      return 0;
    }
    head_('leo task');
    const ids = p.planTasks(ctx.plan);
    for (const t of ids) {
      // ASCII, not an em dash: the columns are padded by character count and
      // a multibyte character silently shifts everything to its right.
      const td = p.taskTodo(ctx.tasks, t) || '-';
      info('  ' + t.padEnd(5) + ' ' + td.padEnd(7) + ' ' +
        p.planTaskStatus(ctx.plan, t).padEnd(12) + ' ' + p.planTaskName(ctx.plan, t));
      // Deferred subtasks under a task that is otherwise live. Without this
      // line the only way to discover one is to open the file, and a deferral
      // nobody can see is a deletion.
      const ls = p.taskLaterSubs(ctx.tasks, t);
      if (ls.length) {
        info('  ' + ''.padEnd(5) + ' ' + ''.padEnd(7) + ' ' + 'later'.padEnd(12) + ' ' + ls.join(' ') + ' ');
      }
    }
    if (ids.length === 0) {
      warn('the plan lists no tasks yet');
      return 0;
    }
    process.stderr.write('\n');
    dim('  leo task T1        create it, or show it');
    dim('  leo defer T1 "why"   park it; the loop moves to the next task');
    return 0;
  }

  if (!/^T[0-9]/.test(id)) die('task ids are T1, T2, … — got: ' + id);

  const f = p.taskFile(ctx.tasks, id);

  // --- subtask ------------------------------------------------------------
  if (sub) {
    if (!isFile(f)) die('no file for ' + id + ' yet — create it first: leo task ' + id);
    // Numbered from what is already in the file rather than from a counter
    // kept somewhere else: the file is the only state, so it cannot disagree
    // with itself.
    const body = readIfFile(f) || '';
    const re = new RegExp('^## ' + id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\.[0-9]', 'gm');
    const n = (body.match(re) || []).length + 1;

    if (!ctx.assets.tmplHas('subtask.md')) die('missing template: subtask.md');
    let tmpl = ctx.assets.tmplRead('subtask.md');
    tmpl = rep(tmpl, '<SUBID>', id + '.' + n);
    tmpl = rep(tmpl, '<SUBNAME>', sub);
    fs.appendFileSync(f, tmpl);

    ok('subtask added: ' + id + '.' + n + ' ' + sub);
    dim('  it arrives ungrilled — leo check fails until you record what it settled');
    dim('  not now? leo defer ' + id + '.' + n + ' "why" — deferred subtasks are not grilled');
    return 0;
  }

  // --- show ---------------------------------------------------------------
  // Create-or-show rather than a --show flag: one fewer thing to document,
  // and the destructive path stays behind --force, as `leo plan` already does.
  if (isFile(f) && !force) {
    process.stdout.write(readIfFile(f));
    const td = p.taskTodo(ctx.tasks, id);
    if (td) process.stderr.write('\n' + td + ' done\n');
    return 0;
  }

  // --- create -------------------------------------------------------------
  // An id the plan in flight does not declare. It might be a typo, and it
  // might be a task from another plan -- worth saying, because the fix for
  // the second is a switch and the fix for the first is a different id.
  // Guessing wrong here sends somebody editing the wrong plan's table.
  if (!p.planHasTask(ctx.plan, id)) {
    const own = p.taskOwner(ctx.plans, id);
    if (own) {
      die(id + ' belongs to ' + own + ', not the plan in flight — leo plan --switch ' + own);
    }
    warn(id + ' is not in the plan — add the row, or fix the id');
  }

  // A task nobody intends to do this week does not need a file, a to-do or a
  // grill. Making one anyway is how a deferral quietly turns back into work.
  if (p.planTaskStatus(ctx.plan, id) === 'later') {
    die(id + ' is later work — leo resume ' + id + ' first  (' + p.planLaterWhy(ctx.plan, id) + ')');
  }

  // The to-do the file starts with. This is the one visible thing the TDD
  // capability does: with it on, the first two steps are red-before-green,
  // and with it off the developer's own order applies. `leo check` runs
  // TEST_CMD either way -- the capability governs order, never whether tests
  // happen.
  const adapters = ctx.adapters || caps.loadAdapters(ctx);
  const todo = caps.capState(ctx, adapters, 'tdd') === 'on'
    ? '- [ ] write the test from "Done when" above — the spec, not the implementation\n' +
      '- [ ] run it, watch it FAIL, and confirm it failed for the reason you expect\n' +
      '- [ ] implement the smallest thing that makes it pass\n' +
      '- [ ] run it, watch it pass\n' +
      '- [ ] set ' + id + ' to done in .leo/plan.md'
    : '- [ ] <step>\n- [ ] <step>';

  // Without this the write below produces an empty file and reports success
  // -- a task file with no "Done when" and no to-do, which is worse than no
  // file.
  if (!ctx.assets.tmplHas('task.md')) die('missing template: task.md');

  mkdirp(path.dirname(f));
  const out = ctx.assets.tmplRead('task.md').split('\n').map((line) => {
    let l = line;
    l = rep(l, '<ID>', id);
    l = rep(l, '<NAME>', p.planTaskName(ctx.plan, id));
    l = rep(l, '<FILES>', p.planTaskFiles(ctx.plan, id));
    l = rep(l, '<EST>', p.planTaskEst(ctx.plan, id));
    return l === '<TODO>' ? todo : l;
  }).join('\n');
  fs.writeFileSync(f, out);

  const rel = f.startsWith(ctx.root + path.sep) ? f.slice(ctx.root.length + 1) : f;
  ok('task created: ' + rel.split(path.sep).join('/'));
  dim('  fill in "Done when" first — the to-do falls out of it');
  return 0;
}

module.exports = { run };
