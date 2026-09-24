'use strict';
// The context every command runs against: where the repository is, where
// leo's own files are inside it, and what the session declares.
//
// This is the `ROOT`/`LEO_DIR`/`PLAN`/`MODE` block from lib.sh, resolved once
// and passed around explicitly instead of living in globals. The shell had no
// choice about the globals; a flat namespace is also how `_t` as a loop
// variable once overwrote the temp-file path `session_doc_write` was holding,
// and SESSION.md silently stopped updating from the moment anything was
// deferred -- the one state it exists to report.

const path = require('path');
const { repoRoot } = require('./repo');
const { loadConfig, readIfFile, isFile } = require('./fsx');
const { die } = require('./ui');

// Everything leo owns lives under .leo/. One directory, no surprises.
function makeCtx() {
  const root = repoRoot();
  const leoDir = path.join(root || '.', '.leo');

  const ctx = {
    root,
    leoDir,
    manifest: path.join(leoDir, 'manifest.md'),
    rules: path.join(leoDir, 'rules'),
    // One file per recorded-but-unlanded cycle. `leo record` writes them,
    // `leo commit` reads them all and consumes them.
    records: path.join(leoDir, 'commits'),
    // Which declared tools this cycle actually used. `leo use` appends,
    // `leo check` reads, `leo record` folds it in and clears it.
    used: path.join(leoDir, 'used'),
    reviews: path.join(leoDir, 'reviews'),
    // A change is one plan; a repository has many. Task ids do not restart:
    // P1 owns T1..T3, P2 starts at T4, and no id is ever reused, because a
    // manifest row saying `T4` must mean exactly one task in exactly one
    // plan forever.
    plans: path.join(leoDir, 'plans'),
    current: path.join(leoDir, 'current'),
    sessionFile: path.join(leoDir, 'session'),
    configFile: path.join(leoDir, 'config'),
    sessionDoc: path.join(root || '.', 'SESSION.md'),
  };

  const config = loadConfig(ctx.configFile);
  const session = loadConfig(ctx.sessionFile);
  ctx.config = config;
  ctx.session = session;
  ctx.testCmd = config.TEST_CMD || '';
  ctx.mode = session.MODE || '';

  // The plan in flight, or empty: one line, no parsing.
  const cur = readIfFile(ctx.current);
  ctx.planId = cur === null ? '' : cur.split('\n')[0].replace(/[\s]/g, '');

  // The fallback is not legacy debt, it is the single-plan repository: a
  // .leo/ with a plan.md and no registry is a valid, working install.
  if (ctx.planId) {
    ctx.plan = path.join(ctx.plans, ctx.planId, 'plan.md');
    ctx.tasks = path.join(ctx.plans, ctx.planId, 'tasks');
  } else {
    ctx.plan = path.join(leoDir, 'plan.md');
    ctx.tasks = path.join(leoDir, 'tasks');
  }

  return ctx;
}

function needRepo(ctx) {
  if (!ctx.root) die('not inside a git repository (leo is built on git)');
}

function needLeo(ctx) {
  needRepo(ctx);
  if (!isFile(ctx.configFile) && !require('./fsx').isDir(ctx.leoDir)) {
    die('this repository has no .leo/  (try: leo init)');
  }
}

module.exports = { makeCtx, needRepo, needLeo };
