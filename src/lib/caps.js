'use strict';
// Capabilities: what the session declares, and what the agent is allowed to
// reach for.
//
// A switch is only a switch if something checks it. leo cannot make an agent
// call a tool or stop it calling one -- it runs before and after, not as a
// supervisor. What it can do is require the mark that using something leaves
// behind.
//
// Two kinds of tool, because they leave two different kinds of mark:
//
//   invoked   the agent calls it at a moment -- a code index, a graph query.
//             The mark is the agent saying so: `leo use serena` announces it
//             and writes the ledger in one action, so what you see and what
//             the check reads cannot disagree.
//   ambient   an output filter or context reducer wrapping the whole session.
//             It is not used at a moment, it is in effect. The mark is the
//             adapter's own `present`: on and not actually installed is a
//             failure of the environment, not of the agent's honesty.
//   practice  neither -- TDD is an order of work, gated in its own stage.
//
// The honest limit, stated once: an agent that uses an invoked tool and never
// runs `leo use` is invisible to this. Attestation catches the careless case,
// not the deceptive one. It is still the difference between a switch and a
// label.

const fs = require('fs');
const path = require('path');
const { readIfFile, isFile, isDir, mkdirp } = require('./fsx');
const { warn } = require('./ui');

// The capabilities leo ships with, in display order.
const BUILTIN_CAPS = ['serena', 'graph', 'rtk', 'headroom', 'ponytail', 'caveman', 'tdd'];

const MODES = ['coding', 'debugging', 'learning', 'review', 'exploration'];

// modePolicy <mode> — the built-in default for each capability.
//
// Named rather than positional. The first version returned bare on/off values
// lined up with the capability list, which meant reordering one line silently
// remapped every mode -- and it could not express a capability leo had never
// heard of, which is exactly what an extension is.
//
// Debugging, learning and exploration turn the semantic reducers off: during
// those, the thing that matters is often the thing that looks like noise. RTK
// stays on throughout because its filtering is structural (progress bars,
// repeated lines) rather than a model deciding what you needed to see.
const POLICY = {
  coding:      { serena: 'on', graph: 'off', rtk: 'on', headroom: 'on',  ponytail: 'on',  caveman: 'off', tdd: 'on' },
  debugging:   { serena: 'on', graph: 'on',  rtk: 'on', headroom: 'off', ponytail: 'off', caveman: 'off', tdd: 'on' },
  learning:    { serena: 'on', graph: 'on',  rtk: 'on', headroom: 'off', ponytail: 'off', caveman: 'off', tdd: 'off' },
  review:      { serena: 'on', graph: 'on',  rtk: 'on', headroom: 'on',  ponytail: 'off', caveman: 'off', tdd: 'off' },
  exploration: { serena: 'on', graph: 'on',  rtk: 'on', headroom: 'off', ponytail: 'off', caveman: 'off', tdd: 'off' },
};

function modePolicy(mode) {
  return POLICY[mode] || null;
}

// loadAdapters — leo's own, then the repository's.
//
// A repo adapter with the same name as a built-in wins, so a team whose
// environment needs a different install command does not have to fork leo.
// `.leo/integrations/` is repository code leo loads, exactly as `.leo/config`
// already is -- read an unfamiliar repository's `.leo/` before running leo in
// it, the same as you would its Makefile.
//
// A repository adapter is somebody else's file and leo loads it on every
// command. One syntax error in it would take down `leo check` along with
// everything else, so a repo adapter that throws is skipped with a warning
// rather than being allowed to kill the run. leo's own adapters are not
// wrapped: they are covered by the suite, and a broken one is leo's bug.
function loadAdapters(ctx) {
  const adapters = {};

  // A bundle has no src/integrations/ to glob -- the built-ins are compiled
  // into it. The repository's own adapters are still read from disk below:
  // dropping them would be the easy bug, a bundle that silently cannot load
  // the adapters a team wrote for their own repo.
  if (ctx.bundle) Object.assign(adapters, ctx.bundle.integrations);

  // A leading underscore marks a shared helper rather than an adapter.
  // Without this, src/integrations/_which.js becomes a capability named
  // "_which" -- listed in `leo session`, counted in the fingerprint, and
  // reported as having no adapter, which is true and useless.
  const isAdapterFile = (f) => f.endsWith('.js') && f[0] !== '_';

  const builtinDir = path.join(ctx.leoHome, 'src', 'integrations');
  if (!ctx.bundle && isDir(builtinDir)) {
    for (const f of fs.readdirSync(builtinDir).sort()) {
      if (!isAdapterFile(f)) continue;
      const name = f.slice(0, -3);
      adapters[name] = require(path.join(builtinDir, f));
    }
  }

  const repoDir = ctx.root ? path.join(ctx.root, '.leo', 'integrations') : '';
  if (repoDir && isDir(repoDir)) {
    for (const f of fs.readdirSync(repoDir).sort()) {
      if (!isAdapterFile(f)) continue;
      const name = f.slice(0, -3);
      try {
        adapters[name] = require(path.join(repoDir, f));
      } catch (e) {
        warn(path.join(repoDir, f) + ' does not load — skipped');
      }
    }
  }

  return adapters;
}

// capsList — the built-ins in display order, then whatever the repository
// added. Discovered from files rather than from a list, so adding a
// capability is dropping in a file: same as a command, same as a rule.
function capsList(adapters) {
  const out = BUILTIN_CAPS.filter((c) => adapters[c]);
  for (const name of Object.keys(adapters)) {
    if (out.indexOf(name) === -1) out.push(name);
  }
  return out;
}

// capOver <cap> — the explicit override, or empty. Stored uppercased, so
// `--caveman on` is CAVEMAN=on in the file.
function capOver(ctx, cap) {
  return ctx.session[cap.toUpperCase()] || '';
}

// capState <cap> — what it is actually set to. In order: an explicit
// override, the mode's built-in default, the adapter's own default, then off.
// Empty when there is no session at all.
function capState(ctx, adapters, cap) {
  if (!ctx.mode) return '';
  const over = capOver(ctx, cap);
  if (over) return over;
  const pol = modePolicy(ctx.mode);
  if (pol && Object.prototype.hasOwnProperty.call(pol, cap)) return pol[cap];
  const a = adapters[cap];
  if (a && typeof a.default === 'function') return a.default(ctx.mode);
  return 'off';
}

// capPresent <cap> — 0 installed, 1 missing, 2 leo has no adapter for it.
//
// The third case is real and must stay visible: leo can name a capability it
// cannot detect, and a display that showed that as "missing" would be lying
// about whose fault it is.
//
// The adapter's answer is collapsed to a boolean rather than passed through.
// 2 is leo's word, not the adapter's, and a shell adapter could return it by
// accident -- a `_present` ending in a failed test against a missing file
// exits 2, and the capability then reported as unsupported when it was merely
// not installed.
function capPresent(ctx, adapters, cap) {
  const a = adapters[cap];
  if (!a || typeof a.present !== 'function') return 2;
  try {
    return a.present(ctx) ? 0 : 1;
  } catch (e) {
    return 1;
  }
}

function capKind(adapters, cap) {
  const a = adapters[cap];
  if (a && typeof a.kind === 'function') return a.kind();
  return 'ambient';
}

function capLabel(adapters, cap) {
  const a = adapters[cap];
  if (a && typeof a.label === 'function') return a.label();
  return cap;
}

function capCall(adapters, cap, fn, ctx) {
  const a = adapters[cap];
  if (!a || typeof a[fn] !== 'function') return [];
  const out = a[fn](ctx);
  if (out === undefined || out === null) return [];
  return Array.isArray(out) ? out : [out];
}

// capOneline <cap> — one line an agent can act on without opening anything.
//
// One line, deliberately. This is what `leo agents` writes into AGENTS.md,
// and AGENTS.md is re-read on every request of every session forever.
function capOneline(adapters, cap, ctx) {
  const a = adapters[cap];
  if (a && typeof a.oneline === 'function') return a.oneline();
  const advice = capCall(adapters, cap, 'advice', ctx);
  return advice.length ? advice[0] : '';
}

// capMcp <cap> — the MCP tool names this capability exposes, or empty.
// Empty is a real answer and the common one: most of these are not MCP
// servers at all, and inventing names for them is how an agent ends up
// calling a tool that does not exist and concluding leo is broken.
function capMcp(adapters, cap) {
  const a = adapters[cap];
  if (a && typeof a.mcp === 'function') return a.mcp();
  return '';
}

// --------------------------------------------------------------- ledger --

function usedHas(ctx, cap) {
  const body = readIfFile(ctx.used);
  if (body === null) return false;
  return body.split('\n').some((l) => l.split('\t')[0] === cap);
}

// usedLog <cap> [note] — record one tool use, once per cycle.
//
// Appended rather than rewritten, and deduplicated on the name: the question
// this answers is "which tools built these hunks", which one line each
// answers completely. A line per call would grow with the session and be
// re-read by the agent on every later turn.
function usedLog(ctx, cap, note, now) {
  mkdirp(ctx.leoDir);
  if (usedHas(ctx, cap)) return;
  const line = cap + '\t' + now + (note ? '\t' + note : '') + '\n';
  fs.appendFileSync(ctx.used, line);
}

// usedNote <cap> — the third field, when there is one. DENIED marks a tool
// that was refused and used anyway, which is the one thing here that fails a
// check rather than merely informing it.
function usedNote(ctx, cap) {
  const body = readIfFile(ctx.used);
  if (body === null) return '';
  for (const l of body.split('\n')) {
    const f = l.split('\t');
    if (f[0] === cap) return f[2] || '';
  }
  return '';
}

function usedList(ctx) {
  const body = readIfFile(ctx.used);
  if (body === null) return [];
  return body.split('\n').filter((l) => l !== '').map((l) => l.split('\t')[0]);
}

// --------------------------------------------------------- fingerprint --

// capSignature — every fact about this session that an agent's instructions
// depend on, as one line.
//
// Installed state is in it on purpose. A tool that is ON and was installed
// since the block was written has different instructions -- the agent should
// be told to use it rather than told it is missing -- and a fingerprint over
// the switches alone would call that block current.
function capSignature(ctx, adapters) {
  let s = 'mode=' + (ctx.mode || 'none');
  for (const c of capsList(adapters)) {
    s += ' ' + c + '=' + capState(ctx, adapters, c) + '/' + capPresent(ctx, adapters, c);
  }
  // The skills, by name and size. The block points the agent at
  // `.leo/skills/grilling/SKILL.md`, so a skill that was added, removed or
  // edited changes what that pointer leads to -- and a block still claiming
  // to describe the session would be describing a different one.
  //
  // Size rather than content: this runs on every command that touches the
  // fingerprint, and hashing every skill to notice an edit nobody made is a
  // cost paid constantly for an event that is rare. A skill that changes
  // without changing length is the miss, and it is a far smaller one than
  // not noticing a skill appearing or disappearing at all.
  for (const sk of skillsSignature(ctx)) s += ' ' + sk;
  return s + '\n';
}

// skillsSignature — `<name>:<bytes>` for every vendored skill, sorted.
function skillsSignature(ctx) {
  const out = [];
  if (!ctx.root) return out;
  const dir = path.join(ctx.root, '.leo', 'skills');
  if (!isDir(dir)) return out;
  let names;
  try { names = fs.readdirSync(dir).sort(); } catch (e) { return out; }
  for (const n of names) {
    const f = path.join(dir, n, 'SKILL.md');
    try {
      const st = fs.statSync(f);
      if (st.isFile()) out.push('skill:' + n + '=' + st.size);
    } catch (e) { /* not a skill directory */ }
  }
  return out;
}

// capFingerprint — capSignature, short enough to sit in a comment.
//
// cksum, because that is what the shell build stamped and an existing
// AGENTS.md has one of those in it. Changing the algorithm would make every
// block in every repository read as stale on the next `leo agents --check`.
// This is the POSIX cksum CRC32, reimplemented rather than shelled out to.
const CKSUM_TABLE = (function () {
  const t = new Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i << 24;
    for (let k = 0; k < 8; k++) {
      c = (c & 0x80000000) ? ((c << 1) ^ 0x04c11db7) : (c << 1);
    }
    t[i] = c >>> 0;
  }
  return t;
})();

function cksum(buf) {
  let crc = 0;
  for (let i = 0; i < buf.length; i++) {
    crc = ((crc << 8) ^ CKSUM_TABLE[((crc >>> 24) ^ buf[i]) & 0xff]) >>> 0;
  }
  // POSIX cksum folds the length in, byte by byte, then complements.
  let len = buf.length;
  while (len > 0) {
    crc = ((crc << 8) ^ CKSUM_TABLE[((crc >>> 24) ^ (len & 0xff)) & 0xff]) >>> 0;
    len = Math.floor(len / 256);
  }
  return (~crc) >>> 0;
}

// The shell was `cap_signature | cksum | tr -d ' ' | cut -c1-12`, and cksum
// prints two fields: the CRC and the byte count. Deleting the space
// concatenates them, so the fingerprint is the digits of the CRC followed by
// the digits of the length, truncated to twelve. Reproducing only the CRC
// would silently change every fingerprint ever stamped into an AGENTS.md.
function capFingerprint(ctx, adapters) {
  const sig = Buffer.from(capSignature(ctx, adapters), 'utf8');
  return (String(cksum(sig)) + String(sig.length)).slice(0, 12);
}

module.exports = {
  BUILTIN_CAPS, MODES, modePolicy, loadAdapters, capsList,
  capOver, capState, capPresent, capKind, capLabel, capCall,
  capOneline, capMcp,
  usedHas, usedLog, usedNote, usedList,
  capSignature, capFingerprint, cksum, skillsSignature,
};
