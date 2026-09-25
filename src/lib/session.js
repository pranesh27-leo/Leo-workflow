'use strict';
// SESSION.md: where this session stands, on disk, in markdown, refreshed on
// the way out of every single leo command whether it succeeded or not.
//
// Why a file and not just `leo session --report`: the report is stdout, and
// stdout dies with the terminal. The one moment this is worth anything is the
// moment after something went wrong -- the session dropped, the check failed,
// the agent stopped mid-task -- and in that moment nobody has the scrollback.
//
// Gitignored, like the plan and the manifest: it is the state of one working
// tree at one moment, and the durable record is the commit message.

const { readIfFile, isFile, isDir, writeAtomic } = require('./fsx');
const { changed, linesChanged } = require('./repo');
const plan = require('./plan');
const caps = require('./caps');
const { recordCount } = require('./records');
const { atexitAdd } = require('./exit');

function now() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return d.getUTCFullYear() + '-' + p(d.getUTCMonth() + 1) + '-' + p(d.getUTCDate()) +
    ' ' + p(d.getUTCHours()) + ':' + p(d.getUTCMinutes()) + ' UTC';
}

// sessionDesc — "debugging (caveman=on)" for the commit trailer, or empty.
// Only the overrides are named: a default is the mode, and the mode is
// already there. What a reviewer needs is the part the developer changed by
// hand.
function sessionDesc(ctx, adapters) {
  if (!ctx.mode) return '';
  const over = [];
  for (const c of caps.capsList(adapters)) {
    const o = caps.capOver(ctx, c);
    if (o) over.push(c + '=' + o);
  }
  return ctx.mode + (over.length ? ' (' + over.join(', ') + ')' : '');
}

// manifestSummary — hunks, and how many still have nothing in the Why column.
// The unreviewed count is the number that matters: a manifest row with an
// empty Why is a hunk nobody has accounted for.
function manifestSummary(manifestFile) {
  const body = readIfFile(manifestFile);
  if (body === null) return null;
  let n = 0, blank = 0;
  for (const line of body.split('\n')) {
    if (!/^\| *[0-9NEW]/.test(line)) continue;
    n++;
    // Index 4, not 5: awk -F'|' numbers fields from 1 and $1 is the empty
    // string before the leading pipe, so the manifest's Task column is $5
    // there and [4] here. Getting this wrong reads the Why column instead,
    // and every row with a reason but no task counts as reviewed.
    const t = (line.split('|')[4] || '').replace(/[ \t]/g, '');
    if (t === '') blank++;
  }
  return n + ' hunk(s), ' + blank + ' still unreviewed';
}

// nextStep — which stage this change is in, as the command that advances it.
// Derived from what is on disk; nothing is stored to make it printable, and
// no command refuses to run because of what this returns. It is a reminder,
// not a gate.
function nextStep(ctx) {
  if (!isFile(ctx.plan)) return 'grill the developer, then: leo plan "<name>"';

  const t = plan.taskCurrent(ctx.plan);
  if (t) {
    if (!isFile(plan.taskFile(ctx.tasks, t))) return 'leo task ' + t;
    const td = plan.taskTodo(ctx.tasks, t);
    if (td) {
      const done = parseInt(td.split('/')[0], 10);
      const total = parseInt(td.split('/')[1], 10);
      if (done < total) {
        return 'build ' + t + ' — next: ' + plan.taskNextItem(ctx.tasks, t);
      }
      // Every box ticked but the plan still says otherwise. Without this the
      // reminder jumped to `leo scan` and the remaining tasks were never
      // built -- the status is what moves the work to the next task.
      if (plan.planTaskStatus(ctx.plan, t) !== 'done') {
        return 'set ' + t + ' to done in .leo/plan.md';
      }
    }
  }

  // Every task either done or deferred, and nothing scanned. The change is
  // not finished, it is parked -- and saying "leo scan" here would send the
  // agent to build a manifest for work that was explicitly put off.
  if (!t && !isFile(ctx.manifest)) {
    const later = plan.planLater(ctx.plan);
    if (later.length) {
      return 'every task left is later work (' + later.join(' ') +
        ') — leo resume <id>, or leo plan "<next change>"';
    }
  }

  if (!isFile(ctx.manifest)) return 'leo scan';

  // A blank Task cell is a hunk nobody has accounted for yet, which is the
  // manifest stage rather than the check stage.
  let blank = 0;
  for (const line of (readIfFile(ctx.manifest) || '').split('\n')) {
    if (!/^\| *[0-9NEW]/.test(line)) continue;
    if ((line.split('|')[4] || '').replace(/[ \t]/g, '') === '') blank++;
  }
  if (blank > 0) return 'fill the manifest — ' + blank + ' hunk(s) name no task';

  // The cycle ends at the record, not at the commit. `leo commit` is still
  // the developer's and still lands the change -- it is just no longer the
  // thing that has to happen for this cycle to be finished.
  return 'leo check, then leo record "<subject>" — the commit comes later, and is theirs';
}

function sessionDoc(ctx, adapters) {
  const out = [];
  const w = (s) => out.push(s);

  w('# Session');
  w('');
  w('_Written by leo on every command, including the ones that fail._');
  w('_Generated — do not edit. `' + now() + '`_');
  w('');
  w('| | |');
  w('|---|---|');

  const pn = plan.planName(ctx.plan);
  w('| Plan | ' + (ctx.planId ? ctx.planId + ' — ' : '') + (pn || 'none yet') + ' |');
  w('| Mode | ' + sessionDesc(ctx, adapters) + ' |');
  const st = plan.planStatus(ctx.plan);
  w('| Tasks | ' + (st || 'none declared') + ' |');

  const ct = plan.taskCurrent(ctx.plan);
  if (ct) {
    const td = plan.taskTodo(ctx.tasks, ct);
    w('| In flight | ' + ct + (td ? '  (' + td + ' done)' : '') + ' |');
  }

  const later = plan.planLater(ctx.plan);
  if (later.length) w('| Later | ' + later.join(' ') + ' |');

  w('| Change size | ' + changed('HEAD').length + ' file(s), ' + linesChanged('HEAD') + ' line(s) |');
  w('| Manifest | ' + (manifestSummary(ctx.manifest) || 'none') + ' |');
  w('| Recorded, unlanded | ' + recordCount(ctx.records) + ' cycle(s) |');
  w('| Next | ' + nextStep(ctx) + ' |');

  // The tools, because "which tools is this agent allowed to use" is the
  // question that is most expensive to get wrong and least visible after the
  // fact.
  if (ctx.mode) {
    w('');
    w('## Tools');
    w('');
    w('| Tool | State | Installed | Used this cycle |');
    w('|---|---|---|---|');
    for (const c of caps.capsList(adapters)) {
      const rc = caps.capPresent(ctx, adapters, c);
      const inst = rc === 0 ? 'yes' : (rc === 1 ? 'NO' : 'no adapter');
      const used = caps.usedHas(ctx, c) ? 'yes' : 'no';
      w('| ' + caps.capLabel(adapters, c) + ' | ' + caps.capState(ctx, adapters, c) +
        ' | ' + inst + ' | ' + used + ' |');
    }
  }

  // Deferred work, spelled out with its reason. A one-word "later" in a
  // table cell is a decision; the reason is the only thing that makes it
  // reviewable.
  if (later.length) {
    w('');
    w('## Later work');
    w('');
    for (const id of later) {
      const why = plan.planLaterWhy(ctx.plan, id);
      w('- **' + id + '** ' + plan.planTaskName(ctx.plan, id) + ' — ' + (why || 'no reason recorded'));
    }
  }

  w('');
  w('## Where the rest of it is');
  w('');
  w('- `AGENTS.md` — how to work here, and the tools this session enabled');
  w('- `ARCHITECTURE.md` — what the system is');
  w('- `CODE_REVIEW.md` — what cycle two argues against');
  w('- `RULES.md` — the rules `leo check` enforces');
  w('- `.leo/workflow.md` — the loop, in full');

  return out.join('\n') + '\n';
}

// registerSessionDoc — write it on the way out, atomically, and never fail.
//
// Called from the exit trap, so every possible failure here is a failure to
// report a failure: it must not print, and it must not change the status the
// command was exiting with.
function registerSessionDoc(ctx) {
  atexitAdd(() => {
    if (!ctx.root) return;
    if (!isDir(ctx.leoDir)) return;
    let body;
    try {
      body = sessionDoc(ctx, ctx.adapters || caps.loadAdapters(ctx));
    } catch (e) {
      return;
    }
    if (!body) return;
    writeAtomic(ctx.sessionDoc, body);
  });
}

module.exports = { now, sessionDesc, sessionDoc, registerSessionDoc, nextStep, manifestSummary };
