'use strict';
// desc: announce that this cycle used a tool, and log it
// usage: leo use <name>
//        leo use --list
//
// Announcing and logging are one action on purpose: what the developer sees
// and what `leo check` reads come from the same call, so they cannot drift
// apart.

const path = require('path');
const { info, dim, ok, warn, err, die, head_, LeoExit } = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const { isFile, readIfFile } = require('../lib/fsx');
const caps = require('../lib/caps');
const { now } = require('../lib/session');

function run(ctx) {
  needRepo(ctx);
  const adapters = ctx.adapters || caps.loadAdapters(ctx);
  ctx.adapters = adapters;
  const list = caps.capsList(adapters);

  let wantList = false, cap = '';
  for (const a of ctx.argv) {
    if (a === '--list') wantList = true;
    else if (a[0] === '-') die('unknown option: ' + a);
    else cap = a;
  }

  if (wantList) {
    if (!isFile(ctx.used)) {
      info('no tool logged this cycle');
      return 0;
    }
    head_('used this cycle');
    for (const line of (readIfFile(ctx.used) || '').split('\n')) {
      if (!line) continue;
      const f = line.split('\t');
      if (!f[0]) continue;
      if (f[2] === 'DENIED') err('  ' + f[0] + '  ' + f[1] + '  — refused, and used anyway');
      else info('  ' + f[0] + '  ' + f[1]);
    }
    return 0;
  }

  if (!cap) die('usage: leo use <name>    (leo session shows what is on)');

  // A name leo has no adapter for is a typo, or a tool nobody wrote an
  // adapter for. Either way it must not be logged: a ledger that accepts
  // anything proves nothing, and `leo check` would then read a name it cannot
  // resolve to a switch.
  if (list.indexOf(cap) === -1) {
    err('no such tool: ' + cap);
    info('');
    info('leo knows: ' + list.join(' '));
    dim('  add one by dropping an adapter in .leo/integrations/ — see the README there');
    throw new LeoExit(1);
  }

  const state = caps.capState(ctx, adapters, cap);
  const label = caps.capLabel(adapters, cap);
  const doc = '.leo/tools/' + cap + '.md';

  // No session at all: nothing is switched on or off, so there is nothing to
  // refuse. Log it anyway -- the record of what built these hunks is worth
  // having whether or not anyone declared a mode.
  if (!ctx.mode) {
    warn('no session declared — nothing is on or off');
    dim('  declare one: leo session --mode coding');
    caps.usedLog(ctx, cap, '', now());
    ok('using ' + label);
    return 0;
  }

  // --- the off switch -----------------------------------------------------
  // Refusing is prevention; recording the attempt is detection. An agent that
  // reads this and stops is the point. An agent that reads it and proceeds
  // has left a line in the ledger that `leo check` fails on, which is the
  // next best thing.
  if (state !== 'on') {
    caps.usedLog(ctx, cap, 'DENIED', now());
    err(label + ' is OFF in this session — do not use it');
    info('');
    info("The mode is the developer's. If this work genuinely needs " + cap + ', say so');
    info('and show them the command. Do not turn it on yourself.');
    info('');
    dim('  theirs to run:  leo session --' + cap + ' on');
    throw new LeoExit(1);
  }

  // Second and later calls in the same cycle announce without re-logging: the
  // developer still sees what is being used, and the ledger stays one line
  // per tool.
  if (caps.usedHas(ctx, cap)) {
    dim('using ' + label + ' (already logged this cycle)');
    return 0;
  }

  // Declared but not installed is worth saying out loud and is not the
  // agent's fault, so it warns rather than refusing. The log still happens:
  // what the agent believed it was using is part of the record either way.
  const rc = caps.capPresent(ctx, adapters, cap);
  if (rc === 1) {
    warn(label + ' is ON but not installed here');
    dim("  the developer's call: leo install " + cap);
  } else if (rc === 2) {
    warn(label + ' has no adapter — leo cannot tell whether it is installed');
  }

  caps.usedLog(ctx, cap, '', now());
  ok('using ' + label);
  // Pointed at, never printed. Seven tool docs inlined would be seven files
  // in the context of a session that needed one -- the whole reason they live
  // on disk instead of in AGENTS.md.
  if (isFile(path.join(ctx.root, doc))) {
    dim('  ' + doc + '   <- how it is meant to be used here');
  }
  return 0;
}

module.exports = { run };
