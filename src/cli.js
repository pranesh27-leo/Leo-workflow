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

// The bundle seam. `leo build` emits one self-contained file that sets this
// before requiring anything, with the templates and every module compiled in.
// When it is absent leo is running from a source tree and reads its own
// install from disk, exactly as before.
//
// One object rather than three globals: the guard below is `if (BUNDLE)`, so
// a bundle that forgot to supply one of them fails loudly at build time
// instead of silently falling back to a filesystem that is not there.
const BUNDLE = global.__LEO_BUNDLE || null;

// Everything leo reads out of its own install goes through here: the version
// and the templates. A single-file build (`leo build`) replaces this module
// with the content compiled in, so a bundle answers from itself and never
// looks for a source tree that is not next to it.
const assets = BUNDLE ? BUNDLE.assets : {
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

// loadCommand <name> — the module for a command, or null.
//
// A command name comes from argv and is used to build a path, so it is
// checked rather than trusted: no separators, no dots, nothing that can climb
// out of src/cmd/ and run a file that is not a leo command.
function loadCommand(name) {
  if (!/^[a-z][a-z0-9-]*$/.test(name)) return null;
  if (BUNDLE) return BUNDLE.commands[name] || null;
  const f = path.join(__dirname, 'cmd', name + '.js');
  try {
    if (!fs.statSync(f).isFile()) return null;
  } catch (e) {
    return null;
  }
  return require(f);
}

function run(argv) {
  let cmd = argv.length > 0 ? argv[0] : 'help';
  const rest = argv.slice(1);

  if (cmd === '-h' || cmd === '--help') cmd = 'help';
  if (cmd === '--version') {
    say('leo ' + assets.version());
    return 0;
  }

  const mod = loadCommand(cmd);
  if (!mod) die('unknown command: ' + cmd + '  (try: leo help)');

  const ctx = makeCtx();
  ctx.leoHome = LEO_HOME;
  ctx.assets = assets;
  ctx.argv = rest;
  ctx.bundle = BUNDLE;

  // SESSION.md is written from the exit trap, so it lands on every path out
  // of every command -- success, failure, and the interrupt in between.
  // Registered after ctx exists and before the command can throw.
  const { registerSessionDoc } = require('./lib/session');
  registerSessionDoc(ctx);

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
