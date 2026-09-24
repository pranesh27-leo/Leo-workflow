'use strict';
// desc: declare what kind of work this is, and what it may reach for
// usage: leo session                     show it
//        leo session --mode <name>       declare the mode
//        leo session --<cap> on|off      override one capability
//        leo session --report            where this change stands
//        leo session --clear             drop the session

const fs = require('fs');
const path = require('path');
const { info, dim, ok, warn, die, head_, C_DIM, C_OFF } = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const { isFile, isDir, mkdirp, readIfFile } = require('../lib/fsx');
const { changed, linesChanged } = require('../lib/repo');
const p = require('../lib/plan');
const caps = require('../lib/caps');
const { recordCount } = require('../lib/records');
const { sessionDesc, nextStep } = require('../lib/session');
const agentsCmd = require('./agents');

function row(k, v) {
  info('  ' + k.padEnd(13) + ' ' + v);
}

function manifestReport(manifestFile) {
  const body = readIfFile(manifestFile);
  if (body === null) return null;
  let n = 0, blank = 0, free = 0;
  for (const line of body.split('\n')) {
    if (!/^\| *[0-9NEW]/.test(line)) continue;
    n++;
    const t = (line.split('|')[5] || '').replace(/[ \t]/g, '');
    if (t === '') blank++;
    else if (t === '-') free++;
  }
  return n + ' hunk(s), ' + (n - blank) + ' reviewed, ' + free + ' serving no task';
}

function run(ctx) {
  needRepo(ctx);
  const adapters = ctx.adapters || caps.loadAdapters(ctx);
  ctx.adapters = adapters;
  const capList = caps.capsList(adapters);

  let mode = '', clear = false, set = false, report = false;
  const wanted = {};

  const argv = ctx.argv.slice();
  while (argv.length) {
    const a = argv.shift();
    if (a === '--clear') { clear = true; continue; }
    if (a === '--report') { report = true; continue; }
    if (a === '--mode') {
      mode = argv.shift() || '';
      if (!mode) die('--mode needs a name (try: leo session --mode coding)');
      if (!caps.modePolicy(mode)) {
        die('unknown mode: ' + mode + '  (coding, debugging, learning, review, exploration)');
      }
      set = true;
      continue;
    }
    if (a.slice(0, 2) === '--') {
      const cap = a.slice(2);
      if (capList.indexOf(cap) === -1) die('unknown option: ' + a);
      const v = argv.shift();
      if (v !== 'on' && v !== 'off') die('--' + cap + ' takes on or off');
      wanted[cap] = v;
      set = true;
      continue;
    }
    die('unexpected argument: ' + a + '  (try: leo session --mode coding)');
  }

  if (clear) {
    try { fs.unlinkSync(ctx.sessionFile); } catch (e) { /* already gone */ }
    ok('session cleared');
    return 0;
  }

  if (set) {
    // A new mode resets the overrides: the mode is a fresh set of defaults,
    // and carrying a hand-set capability across a mode change is how someone
    // ends up debugging with the prose compressor still on. Overrides given
    // on the same command line still apply -- they were asked for with the
    // mode in view.
    if (mode) {
      ctx.mode = mode;
      for (const c of capList) delete ctx.session[c.toUpperCase()];
    } else if (!ctx.mode) {
      die('no session yet — start one: leo session --mode coding');
    }

    for (const c of capList) {
      if (wanted[c]) ctx.session[c.toUpperCase()] = wanted[c];
    }

    mkdirp(ctx.leoDir);
    const out = ['# leo session — written by `leo session`. Read by `leo check`.', '',
      'MODE=' + ctx.mode];
    for (const c of capList) {
      const o = caps.capOver(ctx, c);
      if (o) out.push(c.toUpperCase() + '=' + o);
    }
    fs.writeFileSync(ctx.sessionFile, out.join('\n') + '\n');

    // The tools block in AGENTS.md now describes the session that was in
    // effect a moment ago. Saying so here is the cheapest place to catch it:
    // this is the only command that can make it stale, and the agent reading
    // AGENTS.md has no way to know the file moved under it.
    const agentsFile = path.join(ctx.root, 'AGENTS.md');
    const body = readIfFile(agentsFile);
    if (body !== null && body.indexOf('<!-- leo:tools begin') !== -1) {
      if (!agentsCmd.isCurrent(ctx, adapters)) {
        warn('AGENTS.md now describes the previous session — leo agents --auto');
      }
    }
  }

  // --- report -------------------------------------------------------------
  // Where the change stands, from what leo already has. Nothing new is stored
  // to make this printable.
  //
  // There is no token or savings figure here, and there will not be one.
  // Every tool named above measures a different thing against a different
  // denominator, over buffers that overlap; adding them produces a number
  // that is false.
  if (report) {
    head_('leo session report');
    const pn = p.planName(ctx.plan);
    if (pn) row('Change', (ctx.planId ? ctx.planId + ' — ' : '') + pn);
    row('Mode', ctx.mode ? sessionDesc(ctx, adapters) : 'none declared');

    const on = [], missing = [];
    for (const c of capList) {
      if (caps.capState(ctx, adapters, c) !== 'on') continue;
      on.push(c);
      if (caps.capPresent(ctx, adapters, c) === 1) missing.push(c);
    }
    if (on.length) row('Declared', on.join(', '));
    if (missing.length) row('Not installed', missing.join(', '));

    const st = p.planStatus(ctx.plan);
    if (st) row('Tasks', st);
    // Deferred work, named. "3 of 7 done" with no further comment is how a
    // parked task turns into a forgotten one.
    const later = p.planLater(ctx.plan);
    if (later.length) row('Later', later.join(' ') + '  (leo defer --list)');
    const ct = p.taskCurrent(ctx.plan);
    if (ct) {
      const td = p.taskTodo(ctx.tasks, ct);
      if (td) row('To-do', ct + '  ' + td + ' done');
    }
    row('Change size', changed('HEAD').length + ' file(s), ' + linesChanged('HEAD') + ' lines');

    const mr = manifestReport(ctx.manifest);
    if (mr) {
      row('Manifest', mr);
      const tests = /^Tests: *(.*)$/m.exec(readIfFile(ctx.manifest) || '');
      row('Tests', tests ? tests[1] : '');
    } else {
      row('Manifest', 'none — run: leo scan');
    }

    // Cycles finished but not landed. Without this row the report would show
    // a change with no manifest and nothing to approve, which is what a
    // change that has not started looks like -- and after a disconnect that
    // is exactly the wrong thing to believe.
    const rn = recordCount(ctx.records);
    if (rn > 0) {
      row('Recorded', rn + ' cycle(s), none in git — leo commit --list');
      row('Approval', 'PENDING — leo commit lands all ' + rn + ' as one, and is yours');
    } else if (isFile(ctx.manifest)) {
      row('Approval', 'PENDING — leo record ends this cycle, leo commit is yours');
    } else {
      row('Approval', 'nothing to approve yet');
    }

    row('Next', nextStep(ctx));

    // Whether the instructions the agent is reading describe this session. A
    // stale tools block is worse than none: it is believed.
    const agentsFile = path.join(ctx.root, 'AGENTS.md');
    const ab = readIfFile(agentsFile);
    if (ab !== null && ab.indexOf('<!-- leo:tools begin') !== -1) {
      row('AGENTS.md', agentsCmd.isCurrent(ctx, adapters) ? 'current' : 'STALE — leo agents --auto');
    } else {
      row('AGENTS.md', 'no tools block — leo agents --ask, then --auto');
    }
    row('This report', 'also written to SESSION.md, on every command');

    process.stderr.write('\n');
    dim('  no token figures here on purpose: the tools above measure different');
    dim('  things over overlapping buffers, and summing them would be fiction.');
    return 0;
  }

  if (!ctx.mode) {
    warn('no session — start one: leo session --mode coding');
    dim('  coding  debugging  learning  review  exploration');
    return 0;
  }

  // --- show ---------------------------------------------------------------
  const label = (c) => caps.capLabel(adapters, c);

  // The note says one thing only: leo names this capability but has no
  // adapter for it. Derived rather than written down, because the
  // hand-written version went stale the day an adapter was added and then
  // contradicted the dependencies block three lines further down.
  const note = (c) => {
    if (caps.capState(ctx, adapters, c) !== 'on') return '';
    return caps.capPresent(ctx, adapters, c) === 2 ? 'no adapter' : '';
  };

  head_('leo session');
  info('  Mode: ' + ctx.mode);

  const group = (title, list) => {
    const present = list.filter((c) => capList.indexOf(c) !== -1);
    if (!present.length) return;
    head_(title);
    for (const c of present) {
      const s = caps.capState(ctx, adapters, c).toUpperCase();
      const by = caps.capOver(ctx, c) ? '  (you)' : '';
      const nt = note(c);
      const ntf = nt ? '  ' + C_DIM + nt + C_OFF : '';
      if (by || ntf) info('  ' + label(c).padEnd(13) + ' ' + s.padEnd(4) + by + ntf);
      else info('  ' + label(c).padEnd(13) + ' ' + s);
    }
  };

  // Anything the list gained that leo does not ship with came from
  // .leo/integrations/, and gets its own heading rather than being filed
  // under one of leo's two.
  const extra = capList.filter((c) => caps.BUILTIN_CAPS.indexOf(c) === -1);

  group('code intelligence', ['serena', 'graph']);
  group('efficiency', ['rtk', 'headroom', 'ponytail', 'caveman']);
  // Its own heading. TDD does not mediate what the agent sees -- it says what
  // order the work is done in -- and filing it under efficiency would be a
  // lie about what it is.
  group('practice', ['tdd']);
  group('extensions', extra);

  // Which runtime the vendored skills are wired for. leo installs them into
  // .claude/skills/ and does not guess at Cursor's or Codex's conventions, so
  // a team on something else can see at a glance that this part is not for
  // them. Printed rather than inferred: a skill nobody can see is the bug
  // this whole section exists because of.
  const skillsDir = path.join(ctx.root, '.claude', 'skills');
  if (isDir(skillsDir)) {
    const sk = fs.readdirSync(skillsDir)
      .filter((d) => isFile(path.join(skillsDir, d, 'SKILL.md')));
    if (sk.length) {
      head_('skills');
      info('  ' + sk.join(', ').padEnd(13) + ' wired for Claude Code (.claude/skills/)');
    }
  }

  // Always on, in every mode, and not settable from here. That is the point
  // of the tool: the capabilities above change what the agent sees, and none
  // of them gets to change what leo checks.
  head_('engineering controls');
  for (const c of ['Plan', 'Task IDs', 'Manifest', 'Rules', 'Tests', 'Human commit']) {
    info('  ' + c.padEnd(13) + ' ' + C_DIM + 'ON   always' + C_OFF);
  }

  // --- conflicts ----------------------------------------------------------
  // Between what is declared, not between what is installed: a mode that
  // turns on two tools that fight is worth saying so even on a machine with
  // neither.
  if (caps.capState(ctx, adapters, 'rtk') === 'on' &&
      caps.capState(ctx, adapters, 'headroom') === 'on') {
    head_('conflicts');
    info('  RTK and Headroom both reduce what the agent reads.');
    dim('    RTK filters shell output structurally; Headroom compresses the');
    dim('    context semantically, and sees RTK\'s output already dense. The');
    dim('    second pass returns less than the first and adds a failure mode');
    dim('    the first does not have. Running both is a choice, not a mistake.');
    dim('    The reason to drop one is detail work, which the mode already');
    dim('    does for you. By hand: leo session --headroom off');
  }

  // --- dependencies -------------------------------------------------------
  // Only what is on: a capability you turned off is not a dependency. A
  // missing tool is a warning and never an error. leo works with none of
  // these installed, and that is the property this whole design exists to
  // protect.
  head_('dependencies');
  let missingCount = 0;
  for (const c of capList) {
    if (caps.capState(ctx, adapters, c) !== 'on') continue;
    const rc = caps.capPresent(ctx, adapters, c);
    let state;
    if (rc === 0) state = 'installed';
    else if (rc === 1) { state = 'MISSING'; missingCount++; }
    else state = 'no adapter';
    info('  ' + label(c).padEnd(13) + ' ' + state);
    // The instruction file, printed from here rather than by each adapter.
    // Guarded on the file: an extension with no doc must print nothing rather
    // than a path to a file that is not there -- an agent reading a missing
    // file learns nothing and proceeds as though it had been told nothing.
    const doc = path.join(ctx.leoDir, 'tools', c + '.md');
    if (isFile(doc) && rc !== 2) {
      const rel = doc.startsWith(ctx.root + path.sep) ? doc.slice(ctx.root.length + 1) : doc;
      info('      instructions: ' + rel.split(path.sep).join('/'));
    }
    // Installed: what to do with it. Missing: how to get it. Neither, if leo
    // has no adapter -- there is nothing honest to say.
    let lines = [];
    if (rc === 0) lines = caps.capCall(adapters, c, 'advice', ctx);
    else if (rc === 1) lines = caps.capCall(adapters, c, 'hint', ctx);
    for (const l of lines) info('      ' + l);
  }

  process.stderr.write('\n');
  if (missingCount > 0) {
    warn(missingCount + ' enabled capability(s) not installed — leo works without them');
    dim('  install one above, or drop it here: leo session --<name> off');
  }
  // Two lines, and this is the one place the port deliberately does NOT match
  // the shell byte for byte. core/cmd/session.sh passes this string to a `dim`
  // built on `printf '%s\n'`, so the embedded \n was never interpreted and the
  // developer saw a literal backslash-n in the middle of a sentence. Nothing
  // asserts on it, and reproducing a visible typo buys fidelity to a bug.
  dim('  leo does not install these. It does check them: a tool that is ON and');
  dim('  installed must be announced with leo use, or leo check fails.');
  return 0;
}

module.exports = { run };
