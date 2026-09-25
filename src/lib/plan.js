'use strict';
// The plan and task model.
//
// A plan is a markdown document a human reads and edits, and its task list is
// a markdown table. That is the whole storage format on purpose: the plan has
// to survive being opened in an editor, reviewed in a diff, and argued with.
// Nothing here writes a format a person cannot fix by hand.
//
// The table's columns are positional, and the positions are the template's:
//
//   | #  | Task          | Files   | Est LOC | Status  |
//   | T1 | <first task>  | <files> | <n>     | pending |
//
// splitting on "|" gives a leading empty cell, so the id is index 1, name 2,
// files 3, est 4, status 5. The shell used awk's 1-based $2..$6 for the same
// cells; the numbers differ by one because awk counts fields and this counts
// array slots, not because the format changed.

const fs = require('fs');
const path = require('path');
const { readIfFile, isFile, isDir } = require('./fsx');

// A task row starts with "| T" and a digit. Anything else in the document --
// prose, the Later list, the budget -- is not a task, and a looser match here
// would turn a sentence mentioning T1 into a phantom row.
const TASK_ROW = /^\|\s*T[0-9]/;

function cells(line) {
  return line.split('|').map((c) => c.trim());
}

// planRows — every task row in a plan file, parsed once.
function planRows(planFile) {
  const body = readIfFile(planFile);
  if (body === null) return [];
  const rows = [];
  for (const line of body.split('\n')) {
    if (!TASK_ROW.test(line)) continue;
    const c = cells(line);
    rows.push({
      id: (c[1] || '').replace(/\s/g, ''),
      name: c[2] || '',
      files: c[3] || '',
      est: c[4] || '',
      status: (c[5] || '').replace(/\s/g, ''),
    });
  }
  return rows;
}

function planTasks(planFile) {
  return planRows(planFile).map((r) => r.id);
}

function planHasTask(planFile, id) {
  return planTasks(planFile).indexOf(id) !== -1;
}

function planRow(planFile, id) {
  return planRows(planFile).find((r) => r.id === id) || null;
}

function planTaskName(planFile, id) {
  const r = planRow(planFile, id);
  return r ? r.name : '';
}

function planTaskStatus(planFile, id) {
  const r = planRow(planFile, id);
  return r ? r.status : '';
}

function planTaskEst(planFile, id) {
  const r = planRow(planFile, id);
  return r ? r.est : '';
}

function planTaskFiles(planFile, id) {
  const r = planRow(planFile, id);
  return r ? r.files : '';
}

// planName — the title, from the "# Plan: " heading.
function planName(planFile) {
  const body = readIfFile(planFile);
  if (body === null) return '';
  for (const line of body.split('\n')) {
    const m = /^# Plan: *(.*)$/.exec(line);
    if (m) return m[1];
  }
  return '';
}

// planEst — the declared budget, from the "est: <n> LOC" line.
function planEst(planFile) {
  const body = readIfFile(planFile);
  if (body === null) return '';
  for (const line of body.split('\n')) {
    const m = /^est: *([0-9]+)/.exec(line.trim());
    if (m) return m[1];
  }
  return '';
}

// planStatus — the one-line summary the session document and `leo check`
// both print: how many tasks, how many done, what is in flight, what is next.
function planStatus(planFile) {
  const rows = planRows(planFile);
  if (rows.length === 0) return '';
  let total = 0, done = 0, later = 0, next = '';
  const doing = [];
  for (const r of rows) {
    total++;
    if (r.status === 'done') done++;
    else if (r.status === 'later') later++;
    else if (r.status === 'in-progress') doing.push(r.id);
    else if (next === '') next = r.id;
  }
  let s = done + ' of ' + total + ' done';
  if (later) s += ', ' + later + ' later';
  if (doing.length) s += '  |  in progress: ' + doing.join(',');
  else if (next) s += '  |  next: ' + next;
  else if (later) s += '  |  nothing left but later work';
  return s;
}

// taskCurrent — the task the work is on: the in-progress one, else the first
// that is not done and not deferred. Empty when the plan declares none.
function taskCurrent(planFile) {
  const rows = planRows(planFile);
  const doing = rows.find((r) => r.status === 'in-progress');
  if (doing) return doing.id;
  const pending = rows.find((r) => r.status !== 'done' && r.status !== 'later');
  return pending ? pending.id : '';
}

// planLater — the ids parked in later work, space separated, as the shell
// printed them.
function planLater(planFile) {
  return planRows(planFile).filter((r) => r.status === 'later').map((r) => r.id);
}

// planLaterWhy — the reason `leo defer` wrote under "## Later".
//
// The status cell says a task is deferred; only this says why. A deferral
// without a reason is indistinguishable from a task somebody forgot, which
// is why `leo defer` refuses to write one.
function planLaterWhy(planFile, id) {
  const body = readIfFile(planFile);
  if (body === null) return '';
  let inside = false;
  for (const raw of body.split('\n')) {
    if (/^## Later/.test(raw)) { inside = true; continue; }
    if (inside && /^## /.test(raw)) break;
    if (!inside || !/^- /.test(raw)) continue;
    let line = raw.replace(/^- /, '');
    const rowId = line.split(' ')[0];
    if (rowId !== id) continue;
    // Strip the id, then everything up to the first real word. The separator
    // is an em dash, and a byte-wise character class does not reliably match
    // one -- so this skips non-alphanumerics rather than naming the dash.
    line = line.replace(/^[^ ]*/, '').replace(/^[^A-Za-z0-9]*/, '');
    return line;
  }
  return '';
}

function taskFile(tasksDir, id) {
  return path.join(tasksDir, id + '.md');
}

// taskTodo — "<done>/<total>" across the task file's checkboxes, or empty
// when it has none.
function taskTodo(tasksDir, id) {
  const body = readIfFile(taskFile(tasksDir, id));
  if (body === null) return '';
  let done = 0, total = 0;
  for (const line of body.split('\n')) {
    if (/^- \[[ xX]\]/.test(line)) {
      total++;
      if (/^- \[[xX]\]/.test(line)) done++;
    }
  }
  return total ? done + '/' + total : '';
}

// plansList — every plan id in the registry, in creation order. P10 sorts
// after P9, not between P1 and P2, so the numeric part is compared as a
// number and not as text.
function plansList(plansDir) {
  if (!isDir(plansDir)) return [];
  return fs.readdirSync(plansDir)
    .filter((n) => /^P[0-9]+$/.test(n))
    .filter((n) => isFile(path.join(plansDir, n, 'plan.md')))
    .sort((a, b) => parseInt(a.slice(1), 10) - parseInt(b.slice(1), 10));
}

function planPath(plansDir, id) {
  return path.join(plansDir, id, 'plan.md');
}

function planNextId(plansDir) {
  const ids = plansList(plansDir).map((p) => parseInt(p.slice(1), 10));
  return 'P' + (ids.length ? Math.max.apply(null, ids) + 1 : 1);
}

// taskNextN — the number the next task gets, counted across EVERY plan.
//
// Ids never restart. P1 owning T1..T3 means P2 starts at T4, because a
// manifest row saying `T4` has to name exactly one task in this repository
// forever -- and a per-plan counter would quietly destroy that the day two
// plans both had a T1 and `git log` could no longer tell them apart.
function taskNextN(plansDir, legacyPlanFile) {
  let max = 0;
  const seen = [];
  for (const p of plansList(plansDir)) seen.push(planPath(plansDir, p));
  if (legacyPlanFile && isFile(legacyPlanFile)) seen.push(legacyPlanFile);
  for (const f of seen) {
    for (const id of planTasks(f)) {
      const n = parseInt(id.slice(1), 10);
      if (!isNaN(n) && n > max) max = n;
    }
  }
  return max + 1;
}

// taskOwner — which plan declares this id, or empty.
//
// `leo task T1` while P2 is in flight must not silently act on P1's task.
// The manifest matches on the id alone, so an id claimed by another plan is
// a refusal, not a fallback.
function taskOwner(plansDir, id) {
  for (const p of plansList(plansDir)) {
    if (planHasTask(planPath(plansDir, p), id)) return p;
  }
  return '';
}


// --------------------------------------------------------------- subtasks --
// A subtask is a heading inside its parent's file, never a file of its own.
// One file per subtask turns a five-task change into twenty files, and an
// agent that must read four of them to answer one question pays four reads to
// do it. The parent's reasoning and every child's arrive in a single read.

function subtaskIds(tasksDir, id) {
  const body = readIfFile(taskFile(tasksDir, id));
  if (body === null) return [];
  const out = [];
  for (const line of body.split('\n')) {
    const f = line.split(/\s+/);
    if (f[0] === '##' && f[1] && f[1].indexOf(id + '.') === 0) out.push(f[1]);
  }
  return out;
}

// subtaskState <task-id> <subtask-id> — "later" or empty.
function subtaskState(tasksDir, id, sub) {
  const body = readIfFile(taskFile(tasksDir, id));
  if (body === null) return '';
  let here = false;
  for (const line of body.split('\n')) {
    const f = line.split(/\s+/);
    if (f[0] === '##') here = (f[1] === sub);
    if (here && /^Status: *later/.test(line)) return 'later';
  }
  return '';
}

function taskLaterSubs(tasksDir, id) {
  return subtaskIds(tasksDir, id).filter((s) => subtaskState(tasksDir, id, s) === 'later');
}

// taskUngrilled <task-id> — how many sections still carry the ungrilled
// marker, NOT counting deferred ones.
//
// The exclusion is the point. A subtask that has been put off has not been
// grilled and must not be: grilling it would mean answering questions about
// work that is not happening, and the answers would be guesses. Counting it
// would make `leo check` unpassable until somebody either did the work or
// deleted the subtask, which is exactly the pressure that gets deferrals
// deleted instead of recorded.
function taskUngrilled(tasksDir, id) {
  const body = readIfFile(taskFile(tasksDir, id));
  if (body === null) return 0;
  let later = false, n = 0;
  for (const line of body.split('\n')) {
    if (/^## /.test(line)) later = false;
    if (/^Status: *later/.test(line)) later = true;
    if (line.indexOf('leo:ungrilled') !== -1 && !later) n++;
  }
  return n;
}


// taskNextItem <task-id> — the first unticked box, as plain text. What the
// reminder names when it says "build T1 — next: <this>".
function taskNextItem(tasksDir, id) {
  const body = readIfFile(taskFile(tasksDir, id));
  if (body === null) return '';
  for (const line of body.split('\n')) {
    if (/^- \[ \]/.test(line)) return line.replace(/^- \[ \][ \t]*/, '');
  }
  return '';
}

module.exports = {
  planRows, planTasks, planHasTask, planRow,
  planTaskName, planTaskStatus, planTaskEst, planTaskFiles,
  planName, planEst, planStatus,
  taskCurrent, planLater, planLaterWhy,
  taskFile, taskTodo,
  plansList, planPath, planNextId, taskNextN, taskOwner,
  subtaskIds, subtaskState, taskLaterSubs, taskUngrilled, taskNextItem,
};
