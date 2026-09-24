'use strict';
// The exit trap.
//
// leo writes SESSION.md on the way out of every command, whether it succeeded
// or not -- the command whose session document matters most is `leo check`,
// the one that fails, and that is precisely the command that must not be
// responsible for remembering to write it.
//
// Under bash this was `trap ... EXIT`, plus explicit INT and TERM traps
// because not every bash runs an EXIT trap on a signal. Node's equivalent is
// process.on('exit'), with the same caveat in a different shape: that handler
// cannot await anything, so everything it runs must use the synchronous fs
// API. Hence writeAtomic being sync, and hence this file having no promises
// in it anywhere.

const handlers = [];
let ran = false;

function atexitAdd(fn) {
  handlers.push(fn);
}

// The handler must not change the status it was called with, and must not
// print. A failing command that starts reporting a different error than the
// one it had is worse than one that fails to update a status file.
function runHandlers() {
  if (ran) return;
  ran = true;
  for (const fn of handlers) {
    try {
      fn();
    } catch (e) {
      /* a failure here is a failure to report a failure; stay quiet */
    }
  }
}

function install() {
  process.on('exit', runHandlers);

  // A session killed mid-command is exactly the one somebody comes back to
  // wondering what state it was in. 130 and 143 are the conventional
  // signal exit codes and match what the bash traps used.
  process.on('SIGINT', () => {
    runHandlers();
    process.exit(130);
  });
  process.on('SIGTERM', () => {
    runHandlers();
    process.exit(143);
  });
}

module.exports = { atexitAdd, install, runHandlers };
