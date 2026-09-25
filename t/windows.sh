#!/usr/bin/env bash
# Negative tests for Windows.
#
# This file used to be 79 checks, and most of them are gone -- not because
# Windows got easier, but because leo stopped being a bash program. Every one
# of 0.7.0 through 0.7.4 was a Windows bug, and every one of them had the same
# cause: a POSIX program running on a system that emulates POSIX.
#
#   0.7.0  `syntax error: bad substitution` -- npm read the shebang and ran
#          the first bash.exe on PATH, which was BusyBox from a vendor
#          toolchain
#   0.7.1  `/bin/bash: C:/...: No such file` -- the guard rejected BusyBox and
#          accepted System32\bash.exe, the WSL launcher, which IS bash and
#          cannot open a C: path
#   0.7.2  excluded WSL by path, still guessing at interpreters
#   0.7.3  moved the choice into a Node entry point, which is this design
#   0.7.4  `leo --version` hung for minutes -- grep and wc once per untracked
#          file, and a process spawn on Windows costs an order of magnitude
#          more than it does natively
#
# The checks those needed -- impostor bash, the BASH_VERSION probe, the WSL
# exclusion, the POSIX re-exec guard, leo.ps1's preflight, GNU-only flags,
# shebang portability, the MSYS toolchain -- have nothing left to test. npm's
# generated shims invoke node, and node is what installed the package.
#
# What remains is what was never about bash: the filesystem rules a Unix tree
# can break, paths with spaces, CRLF in the files leo READS, and whether a
# Windows user can install it at all.

set -u
LEOHOME=$(cd -P "$(dirname "$0")/.." && pwd)
LEO="$LEOHOME/leo"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/leo-win.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export NO_COLOR=1
pass=0; fail=0; skip=0

ok()   { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }
note() { skip=$((skip + 1)); printf '  skip  %s\n' "$1"; }

# =========================================================================
printf '\nthe entry point — who chooses the interpreter\n'
# =========================================================================
# The structural assertion, and the one that matters most. npm generates its
# shims from the bin target's SHEBANG: point bin at a shell script and npm
# writes a shim that runs the first thing of that name on PATH, and leo is
# back to arguing with an interpreter somebody else picked. A .js bin means
# the shim invokes node, which is guaranteed present because npm is what
# installed the package.
binfield=$(sed -n 's/.*"leo": *"\([^"]*\)".*/\1/p' "$LEOHOME/package.json" | head -1)
case "$binfield" in
  *.js) ok "package.json bin points at a Node program, not a shell script" ;;
  *) bad "bin is '$binfield' — npm will read its shebang and pick the interpreter" ;;
esac

if head -1 "$LEOHOME/bin/leo.js" 2>/dev/null | grep -q '^#!/usr/bin/env node$'; then
  ok "bin/leo.js asks for node, so npm's shim calls node"
else
  bad "bin/leo.js has no node shebang — npm's shim will not call node"
fi

# leo must not need a shell to start. This is the property the whole port
# bought, and it is cheap to assert: run it with a PATH that has node and
# nothing else on it.
noderoot=$(dirname "$(command -v node)")
out=$(PATH="$noderoot" "$(command -v node)" "$LEOHOME/bin/leo.js" --version 2>&1)
printf '%s' "$out" | grep -q '^leo ' \
  && ok "leo runs with only node on PATH — no shell involved" \
  || bad "leo needs something besides node to start: $out"

# And nothing in the source may reach for a shell to do the work. `shell: true`
# hands Windows an interpreter leo does not control and reintroduces every
# quoting bug the argument-array form makes impossible.
hits=$(grep -rn "shell: *true" "$LEOHOME/src/" 2>/dev/null | grep -v '^[^:]*:[0-9]*: *//' || true)
[ -z "$hits" ] && ok "no spawn uses shell: true" \
               || bad "shell: true reintroduces the interpreter problem: $hits"

# The bash that IS still spawned is deliberate and countable: rule Verify
# blocks and TEST_CMD are the repository's own commands, and running them
# needs a shell by definition. Anything beyond those two is a regression
# toward the per-file spawning that made 0.7.4 hang.
nspawn=$(grep -rn "spawnSync('bash'" "$LEOHOME/src/" 2>/dev/null | grep -vc '^[^:]*:[0-9]*: *//' || true)
[ "${nspawn:-0}" -le 2 ] \
  && ok "bash is spawned in ${nspawn:-0} place(s) — the repo's own commands only" \
  || bad "bash is spawned in ${nspawn} places — something is shelling out again"

# =========================================================================
printf '\nspawning — the 0.7.4 hang, structurally\n'
# =========================================================================
# `leo --version` took minutes on a Zephyr-scale tree because counting lines
# ran two processes per untracked file. Both questions are answered in-process
# now. The assertion is a count of spawns, not a clock: timing is flaky across
# machines, and this bug shipped precisely because nobody could see the cost
# until it was five minutes on a stranger's machine.
SP="$TMP/spawn"; mkdir -p "$SP" && cd "$SP"
git init -q . && git config user.email t@t && git config user.name t
: > base.txt && git add -A && git commit -qm base >/dev/null 2>&1
for i in $(seq 1 60); do printf 'x\n' > "f$i.txt"; done

SPIES="$TMP/spies"; CALLS="$TMP/calls"
mkdir -p "$SPIES"; : > "$CALLS"
for tool in grep wc sed awk; do
  real=$(command -v "$tool")
  [ -n "$real" ] || continue
  cat > "$SPIES/$tool" <<SPY
#!/bin/sh
echo $tool >> "$CALLS"
exec "$real" "\$@"
SPY
  chmod +x "$SPIES/$tool"
done

PATH="$SPIES:$PATH" "$LEO" --version >/dev/null 2>&1
n=$(wc -l < "$CALLS" | tr -d ' ')
[ "${n:-0}" -eq 0 ] \
  && ok "leo --version spawns no grep/wc/sed/awk, with 60 untracked files" \
  || bad "leo --version spawned $n shell utilities — the per-file cost is back"

# And the git calls are counted too, because the expensive one is invisible
# from the outside. `ls-files --others` against leo's SCRATCH index is a full
# uncached walk of the working tree -- the real .git/index carries
# untracked-cache and fsmonitor, a freshly-built one carries neither -- so on
# a large repository it dwarfs everything else leo does while looking exactly
# like a hang.
#
# changed() and linesChanged() each used to build their own index and run
# their own walk, so every command paid for two. The assertion is a count,
# not a clock: one walk per command, and a second one means the pair has
# drifted apart again.
"$LEO" init >/dev/null 2>&1
walks=$(LEO_TIMING=1 "$LEO" session 2>&1 | grep -c 'ls-files --others' || true)
[ "${walks:-0}" -le 1 ] \
  && ok "leo session walks the working tree ${walks:-0} time(s), not twice" \
  || bad "leo session ran $walks untracked scans — changed/linesChanged split again"

ncalls=$(LEO_TIMING=1 "$LEO" session 2>&1 | sed -n 's/^leo: \([0-9]*\) git call.*/\1/p')
[ "${ncalls:-99}" -le 5 ] \
  && ok "leo session makes ${ncalls} git call(s) — the exit trap is not doubling them" \
  || bad "leo session makes ${ncalls} git calls — something is scanning twice"
cd "$LEOHOME"

# =========================================================================
printf '\nCRLF — what an editor does after checkout\n'
# =========================================================================
# .gitattributes stops this for anything arriving through git. It cannot stop
# a developer opening .leo/config in Notepad, and leo READS that file.
#
# Under bash the file was *sourced*, which is why a carriage return was so
# destructive: TEST_CMD="true"^M ran a command that does not exist, and
# MODE=coding^M silently matched no mode at all. Reading rather than sourcing
# removes the class -- but only if the reader actually strips the CR, which is
# what this checks.
CR="$TMP/crlf"; mkdir -p "$CR" && cd "$CR"
git init -q . && git config user.email t@t && git config user.name t
echo x > f.txt && git add -A && git commit -qm base >/dev/null 2>&1
"$LEO" init >/dev/null 2>&1

printf 'TEST_CMD="true"\r\n' > .leo/config
out=$("$LEO" check 2>&1)
printf '%s' "$out" | grep -q 'command not found' \
  && bad "a CR in TEST_CMD reached the shell — the value was not stripped" \
  || ok "a CR in TEST_CMD is stripped before the command runs"

# The silent half, and the worse one: a mode that does not match is not an
# error, it just governs nothing.
printf 'MODE=coding\r\n' > .leo/session
mode=$(node -e '
  var c = require(process.argv[1] + "/src/lib/fsx.js").loadConfig(".leo/session");
  process.stdout.write(JSON.stringify(c.MODE));
' "$LEOHOME" 2>/dev/null)
[ "$mode" = '"coding"' ] \
  && ok "a CR in MODE is stripped — the mode still governs" \
  || bad "MODE parsed as $mode — a CR made the declared mode match nothing"

# And leo says so rather than only surviving it: a stray CR otherwise ends up
# inside the commit message.
out=$("$LEO" check 2>&1)
printf '%s' "$out" | grep -qi 'line ending\|CRLF' \
  && ok "leo check names the file with CRLF" \
  || bad "leo check survived CRLF without mentioning it"
cd "$LEOHOME"

# The policy that stops it at the source. Every file leo reads or executes is
# pinned to LF, permanently, regardless of the developer's git config.
for p in leo bin/leo.js src/cli.js src/lib/ui.js src/cmd/plan.js \
         src/integrations/serena.js templates/AGENTS.md .leo/config; do
  got=$(cd "$LEOHOME" && git check-attr eol -- "$p" 2>/dev/null | sed 's/.*: //')
  [ "$got" = "lf" ] \
    && ok ".gitattributes pins $p to LF" \
    || bad "$p is not pinned to LF (eol=$got) — a Windows checkout rewrites it"
done

# Covered by a glob rather than a list, so the next module is born LF without
# anybody remembering to add a line.
got=$(cd "$LEOHOME" && git check-attr eol -- src/cmd/not-written-yet.js 2>/dev/null | sed 's/.*: //')
[ "$got" = "lf" ] \
  && ok "src/**/*.js is covered by a glob, not a list" \
  || bad "src/*.js is not covered — the next command ships CRLF"

# =========================================================================
printf '\nnpm — can a Windows user install it at all\n'
# =========================================================================
# This assertion used to be the exact opposite: it required an os list, on the
# reasoning that leo is bash and refusing at install time is more honest than
# failing at first run. The premise is gone twice over -- leo is a Node
# program, and node is what runs npm.
if grep -q '"os"' "$LEOHOME/package.json"; then
  if grep -A1 '"os"' "$LEOHOME/package.json" | grep -q 'win32'; then
    ok "package.json's os list includes win32"
  else
    bad "package.json has an os list without win32 — npm refuses to install on Windows"
  fi
else
  ok "package.json places no os restriction on installing"
fi

grep -q '"\.gitattributes"' "$LEOHOME/package.json" \
  && ok ".gitattributes is in the published files list" \
  || bad ".gitattributes is not published — a Windows checkout rewrites leo's own files"

# engines.node is a promise about what the shipped code may use. It is worth
# asserting because the port is free to reach for newer syntax without it.
grep -q '"node"' "$LEOHOME/package.json" \
  && ok "package.json declares the node it needs" \
  || bad "package.json declares no engines.node — nothing states the floor"

# =========================================================================
printf '\npaths with spaces — C:\\Program Files is not an edge case\n'
# =========================================================================
SP2="$TMP/dir with spaces/repo name"
mkdir -p "$SP2" && cd "$SP2"
git init -q . && git config user.email t@t && git config user.name t
printf 'one\n' > "a file.txt"
git add -A && git commit -qm base >/dev/null 2>&1

"$LEO" init >/dev/null 2>&1
[ -f .leo/config ] && ok "leo init works under a path with spaces" \
                   || bad "leo init failed under a path with spaces"
"$LEO" plan "spaced plan" >/dev/null 2>&1
[ -f .leo/plans/P1/plan.md ] && ok "leo plan works under a path with spaces" \
                             || bad "leo plan failed under a path with spaces"
printf 'two\n' >> "a file.txt"
printf 'new\n' > "another file.txt"
out=$("$LEO" scan 2>&1)
printf '%s' "$out" | grep -qi 'wrote .leo/manifest.md' \
  && ok "leo scan works under a path with spaces" \
  || bad "leo scan failed under a path with spaces: $out"
grep -q 'another file.txt' .leo/manifest.md \
  && ok "a filename with a space survives into the manifest whole" \
  || bad "a filename with a space was split"

# A TMPDIR with a space in it, which is where the atomic write lands.
mkdir -p "$TMP/tmp dir"
out=$(TMPDIR="$TMP/tmp dir/" "$LEO" check 2>&1); rc=$?
[ "$rc" = 0 ] || [ "$rc" = 1 ] \
  && ok "leo check survives a TMPDIR containing a space (rc=$rc)" \
  || bad "leo check broke on a spaced TMPDIR (rc=$rc)"
[ -f SESSION.md ] && ok "SESSION.md is still written with a spaced TMPDIR" \
                  || bad "SESSION.md was lost when TMPDIR had a space"
cd "$LEOHOME"

# The atomic write must not depend on TMPDIR at all: rename() is only atomic
# within a filesystem, and %TEMP% on Windows is routinely on another volume.
grep -q "path.dirname(dest)" "$LEOHOME/src/lib/fsx.js" \
  && ok "writeAtomic stages beside the destination, not in TMPDIR" \
  || bad "writeAtomic stages elsewhere — rename across volumes is not atomic"

# =========================================================================
printf '\nWindows filesystem rules a Unix tree can break\n'
# =========================================================================

# Reserved device names. A file called aux.md or con.js cannot be created on
# Windows at all -- npm install fails while unpacking, with an error about a
# path rather than about a name.
reserved=""
for p in $(cd "$LEOHOME" && git ls-files 2>/dev/null); do
  base=$(basename "$p"); stem=$(printf '%s' "${base%%.*}" | tr 'A-Z' 'a-z')
  case "$stem" in
    con|prn|aux|nul|com1|com2|com3|com4|com5|com6|com7|com8|com9|lpt1|lpt2|lpt3|lpt4|lpt5|lpt6|lpt7|lpt8|lpt9)
      reserved="$reserved $p" ;;
  esac
done
[ -z "$reserved" ] && ok "no file uses a reserved Windows device name" \
                   || bad "unpacking fails on Windows for:$reserved"

illegal=$(cd "$LEOHOME" && git ls-files 2>/dev/null | grep -E '[<>:"|?*\\]' || true)
[ -z "$illegal" ] && ok "no filename uses a character Windows forbids" \
                  || bad "illegal on Windows: $illegal"

trailing=$(cd "$LEOHOME" && git ls-files 2>/dev/null | grep -E '[ .]$' || true)
[ -z "$trailing" ] && ok "no filename ends in a dot or a space" \
                   || bad "Windows would rename: $trailing"

dupes=$(cd "$LEOHOME" && git ls-files 2>/dev/null | tr 'A-Z' 'a-z' | sort | uniq -d || true)
[ -z "$dupes" ] && ok "no two tracked paths differ only in case" \
                || bad "case-insensitive collision: $dupes"

longest=$(cd "$LEOHOME" && git ls-files 2>/dev/null | awk '{ print length($0), $0 }' | sort -rn | head -1)
len=${longest%% *}
[ "${len:-0}" -le 120 ] \
  && ok "longest tracked path is ${len} chars (leaves room under MAX_PATH)" \
  || bad "a path is ${len} chars: ${longest#* } — close to MAX_PATH once installed"

# =========================================================================
printf '\nthe bundle\n'
# =========================================================================
# A bundle is a single-file install somebody puts on a Windows PATH, so it
# has to be a Node program too -- and it has to carry the templates, because
# it reads nothing next to itself.
if "$LEO" build --out "$TMP/bundle.js" >/dev/null 2>&1 && [ -f "$TMP/bundle.js" ]; then
  head -1 "$TMP/bundle.js" | grep -q '^#!/usr/bin/env node$' \
    && ok "the bundle asks for node" \
    || bad "the bundle has no node shebang"
  BR="$TMP/bundlerepo"; mkdir -p "$BR" && cd "$BR"
  git init -q . && git config user.email t@t && git config user.name t
  out=$(node "$TMP/bundle.js" --version 2>&1)
  printf '%s' "$out" | grep -q '^leo ' \
    && ok "the bundle runs from a directory containing nothing else" \
    || bad "the bundle cannot run standalone: $out"
  node "$TMP/bundle.js" init >/dev/null 2>&1
  [ -f .leo/workflow.md ] \
    && ok "the bundle carries its templates" \
    || bad "the bundle install produced no templates — it is reading its source tree"
  cd "$LEOHOME"
else
  note "leo build produced no bundle to check"
fi

# =========================================================================
printf '\ndocumentation — a Windows user must be told what they need\n'
# =========================================================================
for doc in README.md GUIDE.md; do
  if grep -qE '^#+ .*[Ww]indows|^\*\*Windows' "$LEOHOME/$doc"; then
    ok "$doc has a Windows section of its own"
  else
    bad "$doc has no Windows section — a Windows user has no idea what to install"
  fi
done

# The install instruction changed with the runtime: naming Git for Windows
# now would send people to install something leo does not use.
grep -qi 'node' "$LEOHOME/README.md" \
  && ok "README names the runtime leo actually needs" \
  || bad "README does not say Windows users need node"

printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
