'use strict';
// desc: run the rules, the documents, the manifest, the grill, the tools, TDD, the budget and the tests
// usage: leo check [--verbose]
//
// Eight checks, in the order that catches mistakes cheapest-first. Read this
// file top to bottom -- there is no plugin system and no hidden ordering.
//
// Quiet on success, loud on failure. This used to print 26 lines every time
// it passed, and in an agent session every one of those lines is re-read on
// every turn for the rest of the session -- a passing check is the least
// informative thing leo prints and it was the most expensive. Warnings still
// come through: terse means "hide what went right", not "hide what you need
// to know".

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const ui = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const { isFile, isDir, readIfFile, hasCr } = require('../lib/fsx');
const { changed, linesChanged } = require('../lib/repo');
const p = require('../lib/plan');
const caps = require('../lib/caps');
const { recordBase } = require('../lib/records');
const { now } = require('../lib/session');

// The buffer. Everything the stages print goes here first; on failure it is
// replayed whole, on success only the warnings and one summary line survive.
//
// The shell did this by swapping fd 2 to a temp file and back. In Node the
// same idea is a local sink, which has the advantage that the summary cannot
// accidentally land inside the buffer it is summarising -- the bug the shell
// version needed an `exec 2>&3 3>&-` dance to avoid.
function makeSink(verbose) {
  const lines = [];
  const emit = (kind, text) => {
    if (verbose) ui[kind](text);
    else lines.push({ kind, text });
  };
  return {
    lines,
    ok: (t) => emit('ok', t),
    err: (t) => emit('err', t),
    warn: (t) => emit('warn', t),
    dim: (t) => emit('dim', t),
    info: (t) => emit('info', t),
    head: (t) => emit('head_', t),
    replay() {
      for (const l of lines) ui[l.kind](l.text);
    },
    warnings() {
      return lines.filter((l) => l.kind === 'warn');
    },
  };
}

// ruleVerify <file> — the shell command under "## Verify", or ''.
function ruleVerify(file) {
  const body = readIfFile(file);
  if (body === null) return '';
  const out = [];
  let inVerify = false, fences = 0;
  for (const line of body.split('\n')) {
    if (/^## Verify/.test(line)) { inVerify = true; continue; }
    if (!inVerify) continue;
    if (/^```/.test(line)) {
      fences++;
      if (fences === 1) continue;
      if (fences === 2) break;
    }
    if (fences === 1) out.push(line);
  }
  return out.join('\n');
}

function manifestRows(manifestFile) {
  const body = readIfFile(manifestFile);
  if (body === null) return [];
  return body.split('\n')
    .filter((l) => /^\| *[0-9NEW]/.test(l))
    .map((l) => l.split('|'));
}

function run(ctx) {
  needRepo(ctx);

  let verbose = false;
  for (const a of ctx.argv) {
    if (a === '--verbose' || a === '-v') verbose = true;
    else if (a[0] === '-') ui.die('unknown option: ' + a);
    else ui.die('unexpected argument: ' + a);
  }

  const adapters = ctx.adapters || caps.loadAdapters(ctx);
  ctx.adapters = adapters;
  const s = makeSink(verbose);

  // The base is whatever `leo scan` reviewed against, so the budget can never
  // be measured against a different starting point than the manifest was.
  let base = 'HEAD';
  if (isFile(ctx.manifest)) {
    const m = /^Base: *(.*)$/m.exec(readIfFile(ctx.manifest) || '');
    base = (m && m[1]) ? m[1] : 'HEAD';
  } else {
    // No manifest and recorded cycles waiting means the manifest was consumed
    // by `leo record`. HEAD would then measure every recorded cycle against
    // the current plan's estimate and fail the budget on work that was
    // already checked and accounted for.
    base = recordBase(ctx.records);
  }
  let fail = false;

  // --- 1. rules -----------------------------------------------------------
  // A rule is a markdown file with a shell command under "## Verify" that
  // exits non-zero when the mistake is present. Zero tokens, ~1s, and it
  // keeps working after the agent that learned the lesson is gone.
  s.head('rules');
  let nRules = 0;
  const ruleFiles = isDir(ctx.rules)
    ? fs.readdirSync(ctx.rules).filter((f) => f.endsWith('.md')).sort()
    : [];
  for (const f of ruleFiles) {
    const id = f.slice(0, -3);
    if (id === 'EXAMPLE' || id === 'TEMPLATE') continue;
    const cmd = ruleVerify(path.join(ctx.rules, f));
    if (!cmd) { s.warn(id + ' has no Verify block — skipped'); continue; }
    nRules++;
    const r = spawnSync('bash', ['-c', cmd], {
      cwd: ctx.root, encoding: 'utf8', windowsHide: true,
      maxBuffer: 64 * 1024 * 1024,
    });
    if (r.status === 0) {
      s.ok(id);
    } else {
      s.err(id + ' violated');
      const out = ((r.stdout || '') + (r.stderr || '')).replace(/\n$/, '');
      if (out) for (const l of out.split('\n')) s.info('       ' + l);
      fail = true;
    }
  }
  if (nRules === 0) s.dim('  no rules yet — write one the next time you fix a real bug');

  // --- 2. documents -------------------------------------------------------
  // Two different failures: a STALE tools block fails, because it is believed
  // -- the agent reads "serena is ON" an hour after the developer switched it
  // off. A MISSING companion document only warns: a repository can reasonably
  // not have written ARCHITECTURE.md yet.
  //
  // The fingerprint is compared inline rather than by shelling out to `leo
  // agents --check`: this runs on every check, and a subprocess that loads
  // the whole library again to answer one string comparison is the kind of
  // cost that is invisible until somebody measures a slow check.
  s.head('documents');
  const agentsFile = path.join(ctx.root, 'AGENTS.md');
  const agentsBody = readIfFile(agentsFile);
  if (agentsBody !== null) {
    if (agentsBody.indexOf('<!-- leo:tools begin') !== -1) {
      const m = /leo:tools begin fingerprint=([a-z0-9]*)/.exec(agentsBody);
      const have = m ? m[1] : '';
      const want = caps.capFingerprint(ctx, adapters);
      if (have === want) {
        s.ok('AGENTS.md describes this session');
      } else if (have === 'none' || have === '') {
        // The placeholder the template ships with. "Never written" and
        // "written and now wrong" are different states and only the second is
        // a lie: an untouched block tells the agent nothing, a stale one
        // tells it something false.
        s.warn('AGENTS.md has no tools block yet — leo agents --ask, then --auto');
      } else {
        s.err('AGENTS.md describes a different session — the agent is reading stale instructions');
        s.dim('  block says ' + have + ', the session is ' + want);
        s.dim('  refresh it: leo agents --auto');
        fail = true;
      }
    } else {
      s.warn('AGENTS.md has no tools block — leo agents --ask, then leo agents --auto');
    }
  }
  const nodoc = ['CONTEXT.md', 'ARCHITECTURE.md', 'CODE_REVIEW.md', 'RULES.md']
    .filter((d) => !isFile(path.join(ctx.root, d)));
  if (nodoc.length) s.warn('missing: ' + nodoc.join(' ') + ' — leo docs --write');

  // Windows line endings in the files leo reads. Never fails a check --
  // surviving a stray CR is not the same as being right, and a developer
  // whose editor defaults to CRLF should hear it once rather than meet it
  // later as a carriage return inside a commit message.
  const crlf = [];
  const rel = (f) => (f.startsWith(ctx.root + path.sep) ? f.slice(ctx.root.length + 1) : f)
    .split(path.sep).join('/');
  for (const f of [ctx.configFile, ctx.sessionFile, ctx.plan, ctx.manifest]) {
    if (hasCr(f)) crlf.push(rel(f));
  }
  if (isDir(ctx.tasks)) {
    for (const f of fs.readdirSync(ctx.tasks).filter((x) => x.endsWith('.md')).sort()) {
      if (hasCr(path.join(ctx.tasks, f))) crlf.push(rel(path.join(ctx.tasks, f)));
    }
  }
  if (crlf.length) {
    s.warn('Windows line endings (CRLF) in: ' + crlf.join(' '));
    s.dim('  leo reads them anyway, but a stray CR ends up inside the commit message.');
    s.dim("  Fix the file:  tr -d '\\r' < FILE > FILE.tmp && mv FILE.tmp FILE");
    s.dim('  Fix it for good: the repository ships a .gitattributes forcing LF.');
  }

  // --- 3. manifest --------------------------------------------------------
  // Every hunk must name the task it serves, and that task must be one the
  // plan actually declared.
  s.head('manifest');
  if (!isFile(ctx.manifest)) {
    s.warn('no manifest — run: leo scan');
  } else {
    const rows = manifestRows(ctx.manifest);
    // Blank means nobody looked at it yet: a failure. An explicit "-" means
    // someone looked and owned the answer: scope creep, reported in lines so
    // the cost is visible.
    let blank = 0, creep = 0, creepLoc = 0;
    // Column indices: awk -F'|' numbers fields from 1 and $1 is the empty
    // string before the leading pipe, so awk's $N is [N-1] here. Task is $5
    // -> [4], Delta is $4 -> [3], Hunk is $3 -> [2]. Off by one reads the
    // Why column as the Task, and every row carrying a reason but no task id
    // then counts as reviewed.
    for (const c of rows) {
      const t = (c[4] || '').replace(/[ \t]/g, '');
      if (t === '') blank++;
      else if (t === '-') {
        creep++;
        const m = /\+([0-9]+)/.exec(c[3] || '');
        if (m) creepLoc += parseInt(m[1], 10);
      }
    }

    if (blank > 0) {
      s.err(blank + ' hunk(s) not reviewed — every row needs Task, Why and If deleted');
      fail = true;
    } else {
      s.ok('every hunk reviewed');
    }

    // A task ID that is not in the plan is an invented justification. This is
    // the one dishonest move that would otherwise sail through the workflow.
    const known = p.planTasks(ctx.plan);
    const used = Array.from(new Set(rows
      .map((c) => (c[4] || '').replace(/[ \t]/g, ''))
      .filter((t) => t !== '' && t !== '-'))).sort();
    if (known.length === 0) {
      s.warn('the plan declares no tasks — nothing to check hunks against');
    } else if (used.length) {
      let invented = false;
      for (const t of used) {
        if (known.indexOf(t) === -1) {
          s.err(t + ' is not a task in the plan — never invent a task ID to justify a hunk');
          invented = true;
          fail = true;
        }
      }
      if (!invented) s.ok('every task ID is one the plan declared');
    }

    if (creep > 0) {
      s.warn(creep + ' hunk(s), ' + creepLoc + ' lines, serve no task — revert, promote or split');
    }

    // And the manifest must still describe the tree it is checked against.
    //
    // `leo scan` takes a snapshot; everything above validates that snapshot's
    // rows. None of it asks whether the snapshot is still true, and work does
    // not stop when the scan runs -- so a file written afterwards had no row,
    // no task and no complaint. "all checks passed", straight into the
    // commit.
    //
    // Only files that appeared. A file the manifest covers and the tree no
    // longer has is a revert, which is a normal thing to do mid-change.
    const covered = new Set();
    for (const c of rows) {
      let h = (c[2] || '').replace(/[ \t`]/g, '');
      h = h.replace(/:[0-9]*$/, '');
      if (h) covered.add(h);
    }
    const appeared = changed(base).filter((f) => !covered.has(f));
    if (appeared.length) {
      s.err('file(s) appeared since the scan and are in no manifest row:');
      for (const f of appeared) s.info('       ' + f);
      s.dim('  the manifest describes a diff that has moved on — rescan it:');
      s.dim('  rm .leo/manifest.md && leo scan');
      fail = true;
    } else {
      s.ok('the manifest still covers the tree');
    }
  }

  // --- 4. grill -----------------------------------------------------------
  // Every task is grilled, and so is every subtask. A task nobody questioned
  // is a task built on whatever the agent assumed, and the assumption becomes
  // code before anyone sees it.
  //
  // Only the task being worked on. Grilling T5 while you are on T1 would mean
  // answering questions about code that does not exist yet.
  s.head('grill');
  const task = p.taskCurrent(ctx.plan);
  if (!task) {
    s.dim('  no task in flight');
  } else if (!isFile(p.taskFile(ctx.tasks, task))) {
    // Not a failure: the task stage simply has not happened yet.
    s.warn(task + ' has no file yet — run: leo task ' + task);
  } else {
    // taskUngrilled, not a bare grep: a deferred subtask carries the
    // ungrilled marker and must not count.
    const un = p.taskUngrilled(ctx.tasks, task);
    if (un > 0) {
      s.err(task + ' is ungrilled (' + un + ' section(s)) — grill it, record what it settled');
      s.dim('  the grill itself: .leo/skills/grilling/SKILL.md');
      s.dim('  no limit on questions or rounds — stop on shared understanding');
      fail = true;
    } else {
      s.ok(task + ' has been grilled');
    }
    const ls = p.taskLaterSubs(ctx.tasks, task);
    if (ls.length) s.dim('  later inside ' + task + ': ' + ls.join(' ') + ' ');
  }

  // dim, not warn. A deferral is stable state, not news: it was already
  // decided, it is in the plan, in SESSION.md and in the commit message, and
  // a warn here would re-enter the agent's context on every turn for as long
  // as the deferral stands.
  const pl = p.planLater(ctx.plan);
  if (pl.length) s.dim('  later work in this plan: ' + pl.join(' ') + '  (leo defer --list)');

  // --- 5. tools -----------------------------------------------------------
  // A tool that is ON must have left its mark; a tool that is OFF must not.
  //
  // Only with a session declared, and only with a cycle in flight. Without
  // the second guard `leo commit` deadlocked: it re-runs the checks, the
  // record had already cleared the manifest and the ledger, and the tools
  // stage failed every landing for evidence that no longer described
  // anything.
  if (ctx.mode && isFile(ctx.manifest)) {
    s.head('tools');
    let tn = 0;
    for (const c of caps.capsList(adapters)) {
      const kind = caps.capKind(adapters, c);
      // A practice is not a tool the agent invokes and gets its own stage.
      if (kind === 'practice') continue;
      tn++;
      const st = caps.capState(ctx, adapters, c);
      const lb = caps.capLabel(adapters, c);

      if (st === 'on') {
        const pr = caps.capPresent(ctx, adapters, c);
        if (pr === 1) {
          // Not installed could not have been used, so never the agent's
          // failure -- and not news either. As a warn it survived the terse
          // filter and put four lines into every passing check, forever.
          s.dim('  ' + lb + ' is ON and not installed — leo install ' + c);
        } else if (pr === 2) {
          s.dim('  ' + lb + ' is ON and leo has no adapter for it — nothing to verify');
        } else if (kind === 'invoked') {
          if (caps.usedHas(ctx, c)) {
            s.ok(lb + ' used');
          } else {
            s.err(lb + ' is ON and was never used — announce it: leo use ' + c);
            s.dim('  or it is not wanted here, which is the developer\'s call:');
            s.dim('  leo session --' + c + ' off');
            fail = true;
          }
        } else {
          s.ok(lb + ' in effect');
        }
      } else if (caps.usedHas(ctx, c)) {
        // The one violation that is unambiguous: the developer switched it
        // off and the ledger says it was used anyway.
        if (caps.usedNote(ctx, c) === 'DENIED') {
          s.err(lb + ' is OFF and was used anyway, after leo refused it');
        } else {
          s.err(lb + ' is OFF and was used anyway');
        }
        s.dim('  the mode is the developer\'s — .leo/used records the attempt');
        fail = true;
      }
    }
    if (tn === 0) s.dim('  no tools declared');
  }

  // --- 6. TDD -------------------------------------------------------------
  // The practice, enforced the same way as the grill: a mark leo can grep.
  // Fails while the "watch it FAIL" step is unticked and there are already
  // hunks in the manifest -- code exists, and nothing ever watched a test
  // fail for the reason it was supposed to.
  //
  // Only when leo seeded the step. A task file written before TDD was turned
  // on has no such line, and inventing a failure for its absence would punish
  // the developer for changing their mind.
  if (caps.capState(ctx, adapters, 'tdd') === 'on' && isFile(ctx.manifest)) {
    s.head('tdd');
    const tt = p.taskCurrent(ctx.plan);
    const tf = tt ? p.taskFile(ctx.tasks, tt) : '';
    if (!tt || !isFile(tf)) {
      s.dim('  no task in flight');
    } else if (/^- \[ \].*watch it FAIL/m.test(readIfFile(tf) || '')) {
      s.err(tt + ' has hunks in the manifest but never watched a test fail');
      s.dim('  - [ ] run it, watch it FAIL, and confirm it failed for the reason you expect');
      s.dim('  tick it once you have, or turn the practice off: leo session --tdd off');
      fail = true;
    } else {
      s.ok(tt + ' watched its test fail first');
    }
  }

  // --- 7. budget ----------------------------------------------------------
  // An overshoot past 2x almost always means the requirement was misread, not
  // that the work was genuinely bigger. Re-plan; do not review harder.
  s.head('budget');
  const est = parseInt(p.planEst(ctx.plan), 10);
  let budgetLine = '';
  if (!est) {
    s.warn("no estimate in the plan — declare one: 'est: <n> LOC'");
  } else {
    const actual = linesChanged(base);
    budgetLine = 'est ' + est + ' LOC / actual ' + actual + ' LOC';
    if (actual > est * 2) {
      s.err('est ' + est + ' LOC, actual ' + actual + ' LOC (over 2x) — re-read the request before reviewing');
      fail = true;
    } else {
      s.ok(budgetLine);
    }
  }

  // --- 8. tests -----------------------------------------------------------
  s.head('tests');
  let result = '';
  if (!ctx.testCmd) {
    s.warn('TEST_CMD unset in .leo/config — leo cannot verify anything for you');
  } else {
    // LEO_YES is leo's own control variable and must not reach the tests.
    // `LEO_YES=1 leo commit` exports it to everything downstream, including
    // TEST_CMD -- and a suite that exercises leo's own refusal to commit
    // without a human then watches that refusal not happen.
    const env = Object.assign({}, process.env);
    delete env.LEO_YES;
    const r = spawnSync('bash', ['-c', ctx.testCmd], {
      cwd: ctx.root, encoding: 'utf8', env, windowsHide: true,
      maxBuffer: 64 * 1024 * 1024,
    });
    const out = ((r.stdout || '') + (r.stderr || '')).replace(/\n$/, '');
    // Not `out === '' ? [] : ...`. The shell piped the output through
    // `sed 's/^/       /'` unconditionally, so a test command that printed
    // nothing still produced one indented blank line. Suppressing it here
    // drops a line the shell emitted.
    const lines = out.split('\n');
    if (r.status === 0) {
      s.ok(ctx.testCmd);
      for (const l of lines.slice(-3)) s.info('       ' + l);
      result = '`' + ctx.testCmd + '` -- passed, ' + now();
    } else {
      s.err(ctx.testCmd + ' failed');
      for (const l of lines.slice(-15)) s.info('       ' + l);
      result = '`' + ctx.testCmd + '` -- FAILED, ' + now();
      fail = true;
    }
  }

  // The Tests: line is evidence, and evidence nobody typed cannot be wishful.
  // leo writes it from the run it just did; a leftover placeholder means no
  // run.
  if (isFile(ctx.manifest)) {
    const body = readIfFile(ctx.manifest) || '';
    if (result) {
      fs.writeFileSync(ctx.manifest, body.split('\n')
        .map((l) => (/^Tests:/.test(l) ? 'Tests: ' + result : l)).join('\n'));
    } else if (/^Tests:.*</m.test(body)) {
      s.err('the manifest still claims nothing about tests — run them and record the real output');
      fail = true;
    }
  }

  // Into the buffer, not straight to stderr. The shell wrote this with
  // `echo >&2` while stderr was still redirected to the buffer file, so it
  // lands at the END of the replay -- a blank line separating the stages from
  // the verdict. Writing it directly here put it at the top instead, before
  // the first stage heading.
  s.info('');

  if (fail) {
    if (!verbose) s.replay();
    // The mode is worth one line here and nowhere else: a check that fails
    // while the session is still set to coding is the moment someone realises
    // they have been debugging for an hour with the reducers on.
    if (ctx.mode) ui.dim('  session mode: ' + ctx.mode);
    ui.die('check failed');
  }

  if (!verbose) {
    // Warnings are not "what went right". A hunk serving no task, a missing
    // manifest, a capability declared and not installed -- each is something
    // the developer has to decide about, and swallowing it to save four lines
    // would be buying tokens with the thing the tokens were for.
    for (const w of s.warnings()) ui.warn(w.text);

    const nhunks = manifestRows(ctx.manifest).length;
    ui.ok('all checks passed');
    ui.info('  ' + nRules + ' rule(s)' +
      (nhunks > 0 ? ', ' + nhunks + ' hunk(s) reviewed' : '') +
      (budgetLine ? ', ' + budgetLine : ''));
    ui.dim('  leo check --verbose to see every stage');
  } else {
    ui.ok('all checks passed');
  }
  return 0;
}

module.exports = { run };
