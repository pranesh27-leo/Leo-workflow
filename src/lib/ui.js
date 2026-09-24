'use strict';
// Output. Every message leo prints goes through here.
//
// The stream split is a contract, not a style: `say` writes to stdout and is
// leo's *answer* -- the thing a script captures. Everything else (progress,
// warnings, errors, the help text) goes to stderr, so `leo plan --list > f`
// gets the list and not the commentary. Changing which stream a message uses
// breaks callers silently, so don't.

const useColor = Boolean(process.stdout.isTTY) && !process.env.NO_COLOR;

const C_OFF = useColor ? '[0m' : '';
const C_DIM = useColor ? '[2m' : '';
const C_B = useColor ? '[1m' : '';
const C_RED = useColor ? '[31m' : '';
const C_GRN = useColor ? '[32m' : '';
const C_YEL = useColor ? '[33m' : '';

// A write to a closed pipe (`leo help | head`) raises EPIPE. bash's printf
// dies quietly there; Node turns it into an unhandled error and a stack
// trace, which is not what `| head` should print.
function write(stream, text) {
  try {
    stream.write(text);
  } catch (e) {
    if (e && e.code === 'EPIPE') return;
    throw e;
  }
}

const say = (...a) => write(process.stdout, a.join(' ') + '\n');
const info = (...a) => write(process.stderr, a.join(' ') + '\n');
const dim = (...a) => write(process.stderr, C_DIM + a.join(' ') + C_OFF + '\n');
const head_ = (...a) => write(process.stderr, '\n' + C_B + a.join(' ') + C_OFF + '\n');
const ok = (...a) => write(process.stderr, C_GRN + 'ok  ' + C_OFF + ' ' + a.join(' ') + '\n');
const warn = (...a) => write(process.stderr, C_YEL + 'warn' + C_OFF + ' ' + a.join(' ') + '\n');
const err = (...a) => write(process.stderr, C_RED + 'ERR ' + C_OFF + ' ' + a.join(' ') + '\n');

// LeoExit carries an exit code out through the call stack. Commands throw it
// instead of calling process.exit, so the exit trap still runs and SESSION.md
// is still written -- a leo that fails is exactly when the session document
// matters most.
class LeoExit extends Error {
  constructor(code) {
    super('leo exit ' + code);
    this.leoExitCode = code;
  }
}

function die(...a) {
  err(...a);
  throw new LeoExit(1);
}

module.exports = {
  say, info, dim, head_, ok, warn, err, die, LeoExit,
  C_OFF, C_DIM, C_B, C_RED, C_GRN, C_YEL,
};
