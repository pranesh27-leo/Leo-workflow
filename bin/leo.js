#!/usr/bin/env node
//
// leo — keep AI-written code reviewable. The npm entry point.
//
// This exists because of what `npm install -g` does on Windows, which is not
// what it looks like it does. npm reads the `#!/usr/bin/env bash` at the top
// of a bin target, generates its own leo.cmd and leo.ps1 into the global bin
// directory, and those invoke the first thing named `bash` on PATH. The
// leo.ps1 that ships inside this package is not on PATH and never runs.
//
// So the interpreter was npm's choice, made from a shebang, and on a real
// machine it chose badly twice over:
//
//   C:\ST\STM32CubeCLT_1.22.0\Make\bin\bash.exe   BusyBox. Not bash. Dies on
//                                                 ${BASH_SOURCE[0]} with
//                                                 "syntax error: bad
//                                                 substitution", naming a
//                                                 line of correct bash.
//   C:\Windows\system32\bash.exe                  The WSL launcher. This one
//                                                 IS bash, and that is worse:
//                                                 it accepts the job and then
//                                                 cannot open C:/Users/...,
//                                                 because WSL sees that
//                                                 repository as /mnt/c/.
//
// Git Bash was installed on that machine and on neither of them.
//
// Pointing bin at this file changes who gets to decide. npm's shims now invoke
// `node`, which is guaranteed to exist because npm is what installed us, and
// the search for a real bash happens here, in one place, with the whole of
// Node available to do it. leo itself keeps its own POSIX guard for the ways
// it gets run that never touch npm: a clone, a symlink, a single-file bundle.
//
// This is a wrapper, not a port. leo is one bash implementation and stays one.

'use strict';

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const PACKAGE_ROOT = path.resolve(__dirname, '..');
const LEO = path.join(PACKAGE_ROOT, 'leo');
const IS_WINDOWS = process.platform === 'win32';

// ---------------------------------------------------------------- probe ----

// Two entries are bash and are still the wrong answer, and on a typical
// Windows developer's PATH both sit ahead of Git Bash. They are rejected by
// path, and rejected BEFORE being executed: probing one can boot a WSL
// distribution or open the Microsoft Store. `wsl leo check` is how to ask for
// WSL on purpose.
const EXCLUDED = /(?:^|[\\/])(?:system32|windowsapps)[\\/]bash\.exe$/i;

// `bash --version` is not the test. BusyBox answers it, with a convincing
// bash version string. Only bash sets BASH_VERSION, and asking for it is one
// expansion every shell will attempt and only bash answers.
function isBash(candidate) {
  if (!candidate || EXCLUDED.test(candidate)) return false;
  try {
    if (!fs.statSync(candidate).isFile()) return false;
  } catch (e) {
    return false;
  }
  const probe = spawnSync(candidate, ['-c', 'printf %s "${BASH_VERSION-}"'], {
    encoding: 'utf8',
    timeout: 10000,
    windowsHide: true,
  });
  return probe.status === 0 && typeof probe.stdout === 'string' && probe.stdout.trim() !== '';
}

// ----------------------------------------------------------- candidates ----

function* onPath(names) {
  const entries = (process.env.PATH || '').split(path.delimiter);
  for (const dir of entries) {
    if (!dir) continue;
    for (const name of names) yield path.join(dir, name);
  }
}

function* candidates() {
  // An explicit override always wins. Someone who sets LEO_BASH and is
  // silently ignored spends a long time wondering which bash ran.
  if (process.env.LEO_BASH) yield process.env.LEO_BASH;

  // Every bash on PATH, not just the first — the first is the one that is not
  // bash.
  yield* onPath(['bash', 'bash.exe']);

  // Git for Windows, located through git.exe rather than guessed. This is the
  // case that matters in practice: the installer puts git on PATH and leaves
  // bash off it, so a machine can have Git Bash and never show it. bash sits
  // a fixed distance from git — git is in <install>/cmd or
  // <install>/mingw64/bin, bash in <install>/bin and <install>/usr/bin.
  for (const git of onPath(['git', 'git.exe'])) {
    let real;
    try {
      if (!fs.statSync(git).isFile()) continue;
      real = fs.realpathSync(git);
    } catch (e) {
      continue;
    }
    const dir = path.dirname(real);
    for (const up of ['..', path.join('..', '..')]) {
      yield path.resolve(dir, up, 'bin', 'bash.exe');
      yield path.resolve(dir, up, 'usr', 'bin', 'bash.exe');
    }
  }

  // The usual installs, including the per-user one that needs no administrator
  // and is therefore what people on locked-down machines have.
  const { ProgramFiles, LOCALAPPDATA, SystemDrive } = process.env;
  const programFilesX86 = process.env['ProgramFiles(x86)'];
  const drive = SystemDrive || 'C:';
  if (ProgramFiles) yield path.join(ProgramFiles, 'Git', 'bin', 'bash.exe');
  if (programFilesX86) yield path.join(programFilesX86, 'Git', 'bin', 'bash.exe');
  if (LOCALAPPDATA) yield path.join(LOCALAPPDATA, 'Programs', 'Git', 'bin', 'bash.exe');
  yield path.join(drive, '\\Program Files\\Git\\bin\\bash.exe');
  yield path.join(drive, '\\Program Files\\Git\\usr\\bin\\bash.exe');
  yield path.join(drive, '\\msys64\\usr\\bin\\bash.exe');
  yield path.join(drive, '\\cygwin64\\bin\\bash.exe');

  // Unix, where this file is a formality and /bin/bash is the answer.
  yield '/bin/bash';
  yield '/usr/bin/bash';
  yield '/usr/local/bin/bash';
  yield '/opt/homebrew/bin/bash';
}

function findBash() {
  const seen = new Set();
  for (const candidate of candidates()) {
    const key = IS_WINDOWS ? candidate.toLowerCase() : candidate;
    if (seen.has(key)) continue;
    seen.add(key);
    if (isBash(candidate)) return candidate;
  }
  return null;
}

// ------------------------------------------------------------ hand over ----

function fail(lines) {
  for (const line of lines) process.stderr.write(line + '\n');
  process.exit(1);
}

const bash = findBash();

if (!bash) {
  fail([
    'ERR  leo needs bash, and there is no real bash on this machine',
    '',
    '     leo is one bash implementation and stays one: a second one in',
    '     PowerShell would be two programs that have to agree about every',
    '     check and every exit code.',
    '',
    '     Git for Windows ships the bash leo wants:',
    '         winget install --id Git.Git -e',
    '         https://git-scm.com/download/win',
    '',
    '     Already have one somewhere else? Point leo at it:',
    "         $env:LEO_BASH = 'C:\\path\\to\\bash.exe'",
    '',
    '     Anything on PATH named bash that is not bash (BusyBox, and the',
    '     bash.exe that vendor toolchains ship) was skipped, as were',
    '     System32\\bash.exe and its WindowsApps alias, which launch WSL.',
    '     Run `wsl leo` to use WSL deliberately.',
  ]);
}

// One line of support diagnostics, off by default. "Which bash did it pick?"
// is the first question worth asking when leo misbehaves on Windows, and it
// used to be unanswerable without reading the source.
if (process.env.LEO_SHOW_BASH) {
  process.stderr.write('leo: using bash at ' + bash + '\n');
}

// Forward slashes, because Git Bash accepts a Windows path in this position
// and converts it itself, while a backslash path handed to some MSYS builds
// arrives with the separators eaten. Arguments go through as an array and are
// never joined into a string: leo takes free text (`leo plan "rate limiting"`,
// `leo defer T3 "waiting on the vendor's key"`) and a hand-rolled quoting pass
// gets that wrong.
const script = IS_WINDOWS ? LEO.replace(/\\/g, '/') : LEO;
const result = spawnSync(bash, [script, ...process.argv.slice(2)], {
  stdio: 'inherit',
  windowsHide: true,
});

if (result.error) {
  fail(['ERR  failed to run leo through ' + bash, '     ' + result.error.message]);
}

// leo's exit codes are part of its contract: 0 success, 1 a check failed,
// 2 leo commit refused because no human was present. Swallowing them would
// make every `if (leo check)` in a build script wrong.
if (result.signal) {
  process.kill(process.pid, result.signal);
} else {
  process.exit(result.status === null ? 1 : result.status);
}
