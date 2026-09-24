'use strict';
// Dispatch.
//
// Adding a command is dropping a file in src/cmd/. There is no registry --
// the same property the shell build had, for the same reason: a registry is a
// second place to remember, and the failure mode is a command that exists and
// cannot be run.

const fs = require('fs');
const path = require('path');
const { die, say, LeoExit } = require('./lib/ui');
const { makeCtx } = require('./lib/ctx');
const exitTrap = require('./lib/exit');

const LEO_HOME = path.resolve(__dirname, '..');

// Everything leo reads out of its own install goes through here: the version
// and the templates. A single-file build (`leo build`) replaces this module
// with the content compiled in, so a bundle answers from itself and never
// looks for a source tree that is not next to it.
const assets = {
  version() {
    return fs.readFileSync(path.join(LEO_HOME, 'VERSION'), 'utf8').trim();
  },
  tmplHas(name) {
    try {
      return fs.statSync(path.join(LEO_HOME, 'templates', name)).isFile();
    } catch (e) {
      return false;
    }
  },
  tmplRead(name) {
    return fs.readFileSync(path.join(LEO_HOME, 'templates', name), 'utf8');
  },
  tmplList() {
    const dir = path.join(LEO_HOME, 'templates');
    const out = [];
    (function walk(d, prefix) {
      let entries;
      try { entries = fs.readdirSync(d, { withFileTypes: true }); } catch (e) { return; }
      for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
        const rel = prefix ? prefix + '/' + e.name : e.name;
        if (e.isDirectory()) walk(path.join(d, e.name), rel);
        else out.push(rel);
      }
    })(dir, '');
    return out;
  },
};

function commandFile(name) {
  // A command name comes from argv and is used to build a path, so it is
  // checked rather than trusted: no separators, no dots, nothing that can
  // climb out of src/cmd/ and run a file that is not a leo command.
  if (!/^[a-z][a-z0-9-]*$/.test(name)) return null;
  const f = path.join(__dirname, 'cmd', name + '.js');
  try {
    return fs.statSync(f).isFile() ? f : null;
  } catch (e) {
    return null;
  }
}

function run(argv) {
  let cmd = argv.length > 0 ? argv[0] : 'help';
  const rest = argv.slice(1);

  if (cmd === '-h' || cmd === '--help') cmd = 'help';
  if (cmd === '--version') {
    say('leo ' + assets.version());
    return 0;
  }

  const file = commandFile(cmd);
  if (!file) die('unknown command: ' + cmd + '  (try: leo help)');

  const ctx = makeCtx();
  ctx.leoHome = LEO_HOME;
  ctx.assets = assets;
  ctx.argv = rest;

  // SESSION.md is written from the exit trap, so it lands on every path out
  // of every command -- success, failure, and the interrupt in between.
  // Registered after ctx exists and before the command can throw.
  const { registerSessionDoc } = require('./lib/session');
  registerSessionDoc(ctx);

  const mod = require(file);
  const rc = mod.run(ctx);
  return typeof rc === 'number' ? rc : 0;
}

function main(argv) {
  exitTrap.install();
  let code = 0;
  try {
    code = run(argv);
  } catch (e) {
    if (e instanceof LeoExit) code = e.leoExitCode;
    else throw e;
  }
  process.exitCode = code;
}

module.exports = { main, assets, LEO_HOME };
