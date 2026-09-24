'use strict';
// desc: install a tool this session declares
// usage: leo install            list what leo can install
//        leo install <name>     install one
//        leo install --all      install everything this session declares
//
// The only command in leo that changes the machine, and the only one besides
// `leo commit` that requires a human at a terminal. Nothing else in leo
// installs anything.

const { spawnSync } = require('child_process');
const { info, dim, ok, warn, err, die, head_, LeoExit } = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const caps = require('../lib/caps');

// state <cap> — one word for where a capability stands, so the listing and
// the install path agree by construction rather than by two people
// remembering.
function state(ctx, adapters, cap) {
  const rc = caps.capPresent(ctx, adapters, cap);
  if (rc === 0) return 'installed';
  if (rc === 2) return 'no adapter';
  const a = adapters[cap];
  return (a && typeof a.install === 'function') ? 'missing' : 'manual';
}

function hintLines(adapters, cap, ctx) {
  return caps.capCall(adapters, cap, 'hint', ctx);
}

// one <cap> — show what would run, ask, run it, then check it worked.
function one(ctx, adapters, cap) {
  const st = state(ctx, adapters, cap);
  if (st === 'installed') { ok(cap + ' is already installed'); return 0; }
  if (st === 'no adapter') { warn(cap + ' has no adapter — leo cannot install it'); return 0; }
  if (st === 'manual') {
    warn(cap + ' has no installer in its adapter — do it by hand:');
    for (const l of hintLines(adapters, cap, ctx)) info('      ' + l);
    return 0;
  }

  const cmds = caps.capCall(adapters, cap, 'install', ctx);
  if (!cmds.length) { warn(cap + ' declares no install command'); return 0; }

  head_('install ' + cap);
  info("  leo will run this. It is not leo's code, and leo has not audited it:");
  process.stderr.write('\n');
  for (const l of cmds) info('      ' + l);
  process.stderr.write('\n');

  if (!process.env.LEO_YES) {
    process.stderr.write('run it? [y/N] ');
    const answer = readLine();
    if (!/^y(es)?$/i.test(answer.trim())) {
      info('skipped ' + cap);
      return 0;
    }
  }

  // `sh -e` so a multi-step installer stops at the first failure instead of
  // carrying on and reporting success from its last line.
  const script = cmds.join('\n');
  const r = spawnSync('sh', ['-e', '-c', script], { stdio: 'inherit', windowsHide: true });
  if (r.status === 0) {
    if (caps.capPresent(ctx, adapters, cap) === 0) {
      ok(cap + ' installed');
      for (const l of caps.capCall(adapters, cap, 'advice', ctx)) info('      ' + l);
    } else {
      // The common cause is a new binary in a directory this shell has not
      // looked at yet, which is a shell problem and not a failure to install.
      warn(cap + ' ran without error but is still not on PATH — open a new shell');
    }
    return 0;
  }
  err(cap + ' install failed');
  info('  by hand:');
  for (const l of hintLines(adapters, cap, ctx)) info('      ' + l);
  return 1;
}

// One line from stdin, synchronously. `leo install` is interactive by
// design and the prompt has to block; there is no async here to await into.
function readLine() {
  const fs = require('fs');
  const buf = Buffer.alloc(1);
  let out = '';
  try {
    while (fs.readSync(0, buf, 0, 1, null) === 1) {
      const ch = buf.toString('utf8');
      if (ch === '\n') break;
      out += ch;
    }
  } catch (e) {
    return 'n';
  }
  return out.replace(/\r/g, '');
}

function run(ctx) {
  needRepo(ctx);
  const adapters = ctx.adapters || caps.loadAdapters(ctx);
  ctx.adapters = adapters;
  const list = caps.capsList(adapters);

  let all = false, want = '';
  for (const a of ctx.argv) {
    if (a === '--all') all = true;
    else if (a[0] === '-') die('unknown option: ' + a);
    else want = a;
  }

  // --- listing ------------------------------------------------------------
  if (!all && !want) {
    head_('leo install');
    for (const c of list) {
      const d = caps.capState(ctx, adapters, c) || 'off';
      info('  ' + c.padEnd(13) + ' ' + state(ctx, adapters, c).padEnd(11) + ' ' + d.toUpperCase());
    }
    process.stderr.write('\n');
    dim('  leo install <name>     install one');
    dim('  leo install --all      install everything this session declares');
    return 0;
  }

  // Past this point leo is going to change the machine, so the same rule as
  // `leo commit`: somebody has to be here to answer for it.
  if (!process.stdin.isTTY && !process.env.LEO_YES) {
    err('leo install needs a human at a terminal');
    info('');
    info('If you are an agent: do not install anything. Show the developer');
    info('`leo install` and let them decide what goes on their machine.');
    info('');
    info('If you are a human whose shell has no tty: LEO_YES=1 leo install ...');
    throw new LeoExit(2);
  }

  if (want) {
    if (list.indexOf(want) === -1) {
      die('unknown capability: ' + want + '  (leo install — to list them)');
    }
    one(ctx, adapters, want);
    return 0;
  }

  // --all: only what this session actually declares. Installing a tool the
  // mode turns off would be leo deciding something the mode already decided.
  if (!ctx.mode) die('no session — start one: leo session --mode coding');
  let n = 0;
  for (const c of list) {
    if (caps.capState(ctx, adapters, c) !== 'on') continue;
    if (state(ctx, adapters, c) !== 'missing') continue;
    one(ctx, adapters, c);
    n++;
  }
  if (n === 0) ok('everything this session declares is already installed');
  return 0;
}

module.exports = { run };
