'use strict';
// Filesystem. Reading, writing, and the two file questions leo keeps asking:
// is this text, and does it have Windows line endings.

const fs = require('fs');
const os = require('os');
const path = require('path');

function readIfFile(file) {
  try {
    if (!fs.statSync(file).isFile()) return null;
  } catch (e) {
    return null;
  }
  try {
    return fs.readFileSync(file, 'utf8');
  } catch (e) {
    return null;
  }
}

function isFile(p) {
  try {
    return fs.statSync(p).isFile();
  } catch (e) {
    return false;
  }
}

function isDir(p) {
  try {
    return fs.statSync(p).isDirectory();
  } catch (e) {
    return false;
  }
}

// hasCr — does this file have Windows line endings? Kept as its own question
// because `leo check` reports it by name: surviving a stray carriage return
// is not the same as it being right, and the CR otherwise ends up inside the
// commit message.
function hasCr(file) {
  const body = readIfFile(file);
  return body !== null && body.indexOf('\r') !== -1;
}

// isText — is this something a human reads, and leo should count lines of?
//
// The rules, which are load-bearing and were each a bug once:
//   * an empty file is TEXT. Every empty __init__.py in a Python project
//     used to arrive in the manifest as `binary`, with no line count and
//     nothing to review.
//   * a file of only blank lines is TEXT, for the same reason.
//   * a file containing a NUL byte is BINARY. That is the whole test, and it
//     is what `grep -I` was doing before this was in-process.
//
// Only the head of the file is read. A NUL in a real binary shows up in the
// first few bytes, and reading a 200MB build artefact in full to answer a
// yes/no question is how `leo scan` became slow on a repository with one.
const TEXT_PROBE_BYTES = 8192;

function isText(file) {
  let fd;
  try {
    fd = fs.openSync(file, 'r');
  } catch (e) {
    return false;
  }
  try {
    const buf = Buffer.alloc(TEXT_PROBE_BYTES);
    const n = fs.readSync(fd, buf, 0, TEXT_PROBE_BYTES, 0);
    if (n === 0) return true; // empty file: text
    return buf.slice(0, n).indexOf(0) === -1;
  } catch (e) {
    return false;
  } finally {
    try { fs.closeSync(fd); } catch (e) { /* already gone */ }
  }
}

// countLines — newline count, which is exactly what `wc -l` returns.
//
// A file whose last line has no trailing newline therefore counts one short.
// That is arguably wrong -- leo is measuring how much a human has to read,
// and that last line is a line -- but it is what every budget, every
// `est vs actual` comparison and every recorded cycle in every existing
// repository was measured with. Changing it here would silently move every
// number leo has ever printed. If it should change, it changes on its own,
// with its own test and its own line in a commit message.
function countLines(file) {
  const body = readIfFile(file);
  if (body === null || body === '') return 0;
  let n = 0;
  for (let i = 0; i < body.length; i++) if (body.charCodeAt(i) === 10) n++;
  return n;
}

// writeAtomic — write, then rename into place.
//
// Called from the exit trap, where every failure is a failure to report a
// failure. A leo killed halfway through writing SESSION.md must leave the
// previous document intact rather than a truncated one, because a truncated
// status file is worse than a stale one: it looks current.
//
// The temp file is made in the destination's own directory, not the system
// temp dir. rename() is only atomic within a filesystem, and on Windows
// %TEMP% is routinely on a different volume from the repository.
function writeAtomic(dest, body, mode) {
  const dir = path.dirname(dest);
  const tmp = path.join(dir, '.leo-tmp-' + process.pid + '-' + Date.now());
  try {
    fs.writeFileSync(tmp, body);
    // 0644: a status file nobody else on the machine can read is a surprise
    // in a shared checkout, and there is nothing private in it that is not
    // already in the repository. chmod is a no-op on Windows, harmlessly.
    try { fs.chmodSync(tmp, mode === undefined ? 0o644 : mode); } catch (e) { /* not POSIX */ }
    fs.renameSync(tmp, dest);
    return true;
  } catch (e) {
    try { fs.unlinkSync(tmp); } catch (e2) { /* nothing to clean */ }
    return false;
  }
}

function mkdirp(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

// loadConfig — parse a `KEY=value` file leo treats as shell.
//
// `.leo/config` and `.leo/session` are plain KEY=value precisely so they need
// no parser. Under bash they were *sourced*, which is why a carriage return
// was so destructive: TEST_CMD="npm test" saved by Notepad set the variable
// to `npm test` plus a CR, and `leo check` then reported
//
//     ERR  npm test failed
//     command not found
//
// ...about a command that is installed and works. MODE=coding was worse,
// because it did not fail: the policy lookup matched `coding` and never
// `coding\r`, so every capability silently fell through to its default and
// the declared mode governed nothing at all.
//
// Reading rather than sourcing removes the class outright -- a CR is stripped
// here and cannot become part of a value -- and it also means a config file
// can no longer execute anything, which sourcing always allowed.
function loadConfig(file) {
  const out = {};
  const body = readIfFile(file);
  if (body === null) return out;
  for (const raw of body.split('\n')) {
    const line = raw.replace(/\r/g, '').trim();
    if (line === '' || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq <= 0) continue;
    const key = line.slice(0, eq).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue;
    let val = line.slice(eq + 1).trim();
    // Strip one layer of matching quotes, the way the shell did.
    if (val.length >= 2 &&
        ((val[0] === '"' && val[val.length - 1] === '"') ||
         (val[0] === "'" && val[val.length - 1] === "'"))) {
      val = val.slice(1, -1);
    }
    out[key] = val;
  }
  return out;
}

function tmpDir() {
  return process.env.TMPDIR || process.env.TEMP || process.env.TMP || os.tmpdir();
}

module.exports = {
  readIfFile, isFile, isDir, hasCr, isText, countLines,
  writeAtomic, mkdirp, loadConfig, tmpDir,
};
