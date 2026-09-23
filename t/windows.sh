#!/usr/bin/env bash
# Negative tests for Windows / PowerShell support.
#
# leo is a bash program. "Working on Windows" does not mean a second
# implementation -- it means one implementation that a Windows user can
# install, invoke from PowerShell, and run against a repository whose paths,
# line endings and temp directory all look nothing like a Unix machine's.
#
# Every way that fails is silent. That is the whole problem, and it is why
# this file is negative tests rather than a happy path:
#
#   CRLF          the script is byte-for-byte correct plus one invisible
#                 character per line, and bash says `$'\r': command not found`
#   the os field  npm refuses to install and the user never sees leo at all
#   spaces        C:\Program Files and C:\Users\John Smith are ordinary paths,
#                 and an unquoted variable splits them into two arguments
#   GNU flags     `sed -i` and `readlink -f` work on Linux, fail on Git Bash,
#                 and fail differently on macOS
#   reserved names  a file called `aux.md` cannot exist on Windows at all
#
# None of these can be caught by running leo on a Mac and watching it pass.
# So most of what follows is a static audit of the shipped tree, plus the
# Windows conditions that CAN be reproduced anywhere -- spaces and CRLF --
# exercised for real.
#
# The PowerShell sections run against a real pwsh when one is present (pwsh
# runs on macOS and Linux too) and degrade to a structural audit when it is
# not. They are never silently skipped: a skip is printed, because a test
# suite that quietly checks nothing is the failure mode this repository has
# already been bitten by once.

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

# absent <label> <pattern> <files...> — the shipped tree must NOT contain a
# pattern. Comments are excluded: this repository discusses the things it
# forbids at length, and a rule that cannot survive being written about is a
# rule nobody can document.
absent() {
  _label="$1"; _pat="$2"; shift 2
  _hits=$(grep -nE "$_pat" "$@" 2>/dev/null | grep -v '^[^:]*:[0-9]*: *#' || true)
  if [ -z "$_hits" ]; then
    ok "$_label"
  else
    bad "$_label"
    printf '%s\n' "$_hits" | sed 's/^/        /' | head -6
  fi
}

# The files that actually ship. Everything below audits this set and not the
# repository, because the repository has tests, fixtures and a dist/ that no
# Windows user will ever receive.
shipped_sh() {
  printf '%s\n' "$LEOHOME/leo" "$LEOHOME/core/lib.sh"
  for f in "$LEOHOME"/core/cmd/*.sh "$LEOHOME"/core/integrations/*.sh; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

# =========================================================================
printf '\nline endings — the one that makes a correct script fail\n'
# =========================================================================

# Proof that this matters, rather than an assertion that it does. A file with
# CRLF is handed to bash and must fail; if it does not, the rest of this
# section is testing nothing.
printf '#!/usr/bin/env bash\r\necho hello\r\n' > "$TMP/crlf-probe.sh"
if bash "$TMP/crlf-probe.sh" >/dev/null 2>&1; then
  note "this bash tolerates CRLF — the CRLF checks below still matter on Git Bash"
else
  ok "a CRLF shell script fails to run (this is what .gitattributes prevents)"
fi

[ -f "$LEOHOME/.gitattributes" ] \
  && ok ".gitattributes exists" \
  || bad ".gitattributes is missing — Windows checkouts get CRLF and leo dies"

# Not "does the file mention lf" but "does git, right now, resolve these paths
# to eol=lf". Asking git is the only answer that cannot drift from what git
# actually does on checkout.
if command -v git >/dev/null 2>&1 && [ -d "$LEOHOME/.git" ]; then
  miss=""
  for p in leo core/lib.sh core/cmd/plan.sh core/cmd/agents.sh \
           core/integrations/serena.sh templates/AGENTS.md \
           templates/workflow.md package.json VERSION .gitignore; do
    got=$(cd "$LEOHOME" && git check-attr eol -- "$p" 2>/dev/null | sed 's/.*: //')
    [ "$got" = "lf" ] || miss="$miss $p:${got:-unset}"
  done
  [ -z "$miss" ] && ok "git resolves every shipped path to eol=lf" \
                 || bad "paths git would check out as CRLF:$miss"

  # The glob has to cover a file that does not exist yet. A new command is a
  # new file in core/cmd/, and the next one must be born LF without anybody
  # remembering to add a line here.
  got=$(cd "$LEOHOME" && git check-attr eol -- core/cmd/not-written-yet.sh 2>/dev/null | sed 's/.*: //')
  [ "$got" = "lf" ] \
    && ok "a command that does not exist yet is already covered by the glob" \
    || bad "core/cmd/*.sh is not covered — the next command ships CRLF"

  # PowerShell is the deliberate exception. Windows PowerShell 5.1 is the one
  # consumer that cares, and CRLF is its native convention.
  got=$(cd "$LEOHOME" && git check-attr eol -- leo.ps1 2>/dev/null | sed 's/.*: //')
  [ "$got" = "crlf" ] \
    && ok "leo.ps1 is eol=crlf, which is what PowerShell wants" \
    || bad "leo.ps1 resolves to ${got:-unset}, expected crlf"
else
  note "not a git checkout — cannot ask git how it would check these out"
fi

# And nothing in the tree has CRLF *now*. .gitattributes governs what git
# writes; this governs what is sitting here to be packed into a tarball.
crlf_now=""
for f in $(shipped_sh); do
  LC_ALL=C grep -q "$(printf '\r')" "$f" 2>/dev/null && crlf_now="$crlf_now ${f#"$LEOHOME"/}"
done
for f in "$LEOHOME"/templates/*.md "$LEOHOME"/templates/*/*.md "$LEOHOME"/templates/*/*/*.md; do
  [ -f "$f" ] || continue
  LC_ALL=C grep -q "$(printf '\r')" "$f" 2>/dev/null && crlf_now="$crlf_now ${f#"$LEOHOME"/}"
done
[ -z "$crlf_now" ] && ok "no shipped file currently contains a carriage return" \
                   || bad "CRLF already in the tree:$crlf_now"

# =========================================================================
printf '\nCRLF at runtime — what an editor does after checkout\n'
# =========================================================================
# .gitattributes cannot stop a developer opening .leo/config in Notepad. leo
# has to survive that, because the failure it produces otherwise blames the
# developer's test runner for something leo did.

mkdir -p "$TMP/crlf" && cd "$TMP/crlf"
git init -q . && git config user.email t@t && git config user.name t
echo one > f.txt && git add -A && git commit -qm init
"$LEO" init >/dev/null 2>&1

# The exact failure: TEST_CMD="true" saved with CRLF used to make leo report
# `true failed -- command not found` about a command that is a shell builtin.
printf 'TEST_CMD="true"\r\n' > .leo/config
out=$("$LEO" check 2>&1 || true)
printf '%s' "$out" | grep -q 'command not found' \
  && bad "a CRLF .leo/config still breaks TEST_CMD" \
  || ok "a CRLF .leo/config does not break TEST_CMD"

# The silent one, which is worse. MODE=coding with a trailing CR never matches
# `coding` in mode_policy, so every capability falls through to its adapter
# default and the declared mode governs nothing -- while `leo session` prints
# "coding" and looks correct.
printf 'MODE=coding\r\n' > .leo/session
probe=$(cat <<'PROBE'
. "$LEO_HOME/core/lib.sh"
printf '%s|%s|%s\n' "${#MODE}" "$(mode_policy "$MODE" | wc -c | tr -d ' ')" "$(cap_state serena)"
PROBE
)
printf '%s\n' "$probe" > "$TMP/probe.sh"
res=$(LEO_HOME="$LEOHOME" bash "$TMP/probe.sh" 2>/dev/null)
mlen=${res%%|*}; rest=${res#*|}; plen=${rest%%|*}; state=${rest##*|}
[ "$mlen" = "6" ] && ok "a CRLF .leo/session yields MODE with no carriage return" \
                  || bad "MODE is $mlen chars, expected 6 — the CR survived"
[ "${plen:-0}" -gt 1 ] && ok "the mode still matches a policy through CRLF" \
                       || bad "mode_policy matched nothing — the declared mode governs nothing"
[ "$state" = "on" ] && ok "capabilities still follow the declared mode" \
                    || bad "cap_state fell through to a default: got '$state'"

# And leo must SAY it found CRLF rather than only coping. Coping silently
# means the stray carriage returns end up inside a commit message.
"$LEO" plan "crlf" >/dev/null 2>&1
out=$("$LEO" check 2>&1 || true)
printf '%s' "$out" | grep -qi 'line ending\|CRLF' \
  && ok "leo check reports the CRLF files by name" \
  || bad "leo check copes with CRLF silently — the CR reaches the commit message"

cd "$LEOHOME"

# =========================================================================
printf '\nnpm — can a Windows user install it at all\n'
# =========================================================================

# The os field is a hard refusal: `npm install -g` on win32 fails outright and
# the user never gets as far as discovering leo needs bash.
if grep -q '"os"' package.json; then
  if grep -A1 '"os"' package.json | grep -q 'win32'; then
    ok "package.json declares an os list that includes win32"
  else
    bad "package.json has an os list without win32 — npm refuses to install on Windows"
  fi
else
  ok "package.json declares no os restriction — Windows can install it"
fi

# npm's cmd-shim reads the shebang of the bin target to decide what to write
# into leo.cmd and leo.ps1. No shebang, or one it cannot parse, and Windows
# gets a shim that tries to execute a bash script as a batch file.
shebang=$(head -1 leo)
case "$shebang" in
  '#!/usr/bin/env bash') ok "the bin target's shebang is one npm's cmd-shim can parse" ;;
  '#!'*bash*)            ok "the bin target has a bash shebang ($shebang)" ;;
  *)                     bad "bin shebang is '$shebang' — cmd-shim cannot make a Windows shim from it" ;;
esac

for f in leo.ps1 .gitattributes; do
  grep -q "\"$f\"" package.json \
    && ok "$f is in the published files list" \
    || bad "$f is not published — Windows users never receive it"
done

# What npm would actually ship, if npm is here to ask.
if command -v npm >/dev/null 2>&1; then
  listing=$(npm pack --dry-run --ignore-scripts --json 2>/dev/null \
            | sed -n 's/.*"path": *"\([^"]*\)".*/\1/p')
  [ -z "$listing" ] && listing=$(npm pack --dry-run --ignore-scripts 2>&1)
  if [ -n "$listing" ]; then
    m=""
    for f in leo.ps1 .gitattributes; do
      printf '%s\n' "$listing" | grep -q "$f" || m="$m $f"
    done
    [ -z "$m" ] && ok "npm pack includes the Windows files" \
                || bad "npm would drop:$m"
  else
    note "npm pack produced no listing"
  fi
else
  note "npm is not installed — cannot check the real pack listing"
fi

# =========================================================================
printf '\nthe PowerShell wrapper\n'
# =========================================================================

PS1F="$LEOHOME/leo.ps1"
if [ ! -f "$PS1F" ]; then
  bad "leo.ps1 is missing — there is no PowerShell entry point"
else
  ok "leo.ps1 exists"

  # It is a wrapper. If it ever grows leo's own vocabulary it has stopped
  # being a wrapper and become a second implementation that has to agree with
  # the first about every check, every message and every exit code.
  absent "leo.ps1 does not reimplement leo" \
    '(manifest|ungrilled|cap_state|plan_status|leo:tools|\.leo/plan)' "$PS1F"

  # Exit codes are part of leo's contract: 0 success, 1 a check failed, 2 the
  # commit refused. A wrapper that swallows them makes every `if (leo check)`
  # in a caller's script wrong.
  grep -q 'exit \$exitCode' "$PS1F" \
    && ok "leo.ps1 propagates leo's exit code" \
    || bad "leo.ps1 does not propagate the exit code — 'a check failed' becomes 'success'"

  # Arguments must pass as an array. Joining them means re-quoting, and leo
  # takes free text: `leo defer T3 "waiting on the vendor's key"` has both a
  # space and an apostrophe in one argument.
  if grep -qE '\$Arguments\s*-join' "$PS1F"; then
    if grep -qE '@Arguments' "$PS1F"; then
      ok "leo.ps1 splats arguments (a -join appears only in a message)"
    else
      bad "leo.ps1 joins arguments into a string — quoting will be wrong"
    fi
  else
    grep -q '@Arguments' "$PS1F" \
      && ok "leo.ps1 splats arguments rather than joining them" \
      || bad "leo.ps1 does not pass arguments through"
  fi

  # A user with no bash must be told what to install, by name.
  for want in 'git-scm.com\|winget' 'LEO_BASH'; do
    grep -q "$want" "$PS1F" \
      && ok "leo.ps1 names $(printf '%s' "$want" | tr -d '\\') in its no-bash message" \
      || bad "leo.ps1 does not mention $want — a user with no bash is stuck"
  done

  # It must not hardcode one bash path and give up.
  n=$(grep -c 'bash\.exe' "$PS1F" || true)
  [ "${n:-0}" -ge 3 ] \
    && ok "leo.ps1 searches several bash locations ($n candidates)" \
    || bad "leo.ps1 checks ${n:-0} bash location(s) — too few to find a real install"

  # CRLF: PowerShell 5.1 is the consumer and CRLF is its convention. The file
  # on disk here may be LF because git normalises on checkout according to
  # .gitattributes, so this checks the attribute rather than the bytes.
  if command -v git >/dev/null 2>&1 && [ -d "$LEOHOME/.git" ]; then
    got=$(cd "$LEOHOME" && git check-attr eol -- leo.ps1 | sed 's/.*: //')
    [ "$got" = "crlf" ] && ok "leo.ps1 will be checked out CRLF on every platform" \
                        || bad "leo.ps1 eol is $got"
  fi

  # Real parse, when a real PowerShell is available. pwsh runs on macOS and
  # Linux, so this is not Windows-only.
  if command -v pwsh >/dev/null 2>&1; then
    if pwsh -NoProfile -NonInteractive -Command "
          \$ErrorActionPreference='Stop'
          \$t=[System.Management.Automation.PSParser]::Tokenize(
               (Get-Content -Raw '$PS1F'), [ref]\$null)
          exit 0" >/dev/null 2>&1; then
      ok "leo.ps1 parses under a real PowerShell"
    else
      bad "leo.ps1 does not parse under PowerShell"
    fi

    # The negative case that matters most: no bash anywhere. It must fail
    # with a non-zero code and a message, not a stack trace.
    out=$(LEO_BASH="$TMP/definitely-not-bash" pwsh -NoProfile -NonInteractive \
            -File "$PS1F" --version 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then
      bad "leo.ps1 succeeded with a bogus LEO_BASH"
    elif printf '%s' "$out" | grep -qi 'LEO_BASH'; then
      ok "leo.ps1 refuses a bogus LEO_BASH and names it"
    else
      bad "leo.ps1 refused a bogus LEO_BASH without saying why: $out"
    fi

    # And the happy path, through the wrapper, on this machine's bash.
    out=$(LEO_BASH="$(command -v bash)" pwsh -NoProfile -NonInteractive \
            -File "$PS1F" --version 2>&1)
    printf '%s' "$out" | grep -q "^leo " \
      && ok "leo.ps1 runs leo end to end through a real PowerShell" \
      || bad "leo.ps1 could not run leo: $out"
  else
    note "pwsh is not installed — leo.ps1 audited structurally, not executed"
  fi
fi

# =========================================================================
printf '\npaths with spaces — C:\\Program Files is not an edge case\n'
# =========================================================================
# Reproducible anywhere: an unquoted variable splits on a space identically on
# every platform. These are the three paths that are routinely spaced on
# Windows and almost never on a developer's Mac.

mkdir -p "$TMP/Program Files/John Smith/my repo"
cd "$TMP/Program Files/John Smith/my repo"
git init -q . && git config user.email t@t && git config user.name t
echo one > f.txt && git add -A && git commit -qm init

"$LEO" init >/dev/null 2>&1 \
  && ok "leo init works in a repository path containing spaces" \
  || bad "leo init failed in a spaced repository path"
printf 'TEST_CMD="true"\n' >> .leo/config
"$LEO" session --mode coding >/dev/null 2>&1
"$LEO" agents --auto >/dev/null 2>&1 \
  && ok "leo agents --auto works in a spaced path" \
  || bad "leo agents --auto failed in a spaced path"
"$LEO" plan "spaced" >/dev/null 2>&1 \
  && ok "leo plan works in a spaced path" \
  || bad "leo plan failed in a spaced path"
"$LEO" defer T1 "why" >/dev/null 2>&1 \
  && ok "leo defer works in a spaced path" \
  || bad "leo defer failed in a spaced path"
[ -f SESSION.md ] && ok "SESSION.md is written in a spaced path" \
                  || bad "SESSION.md missing in a spaced path"

# An install directory with spaces: C:\Program Files\nodejs\node_modules\...
# This is where tmpl_cat reads every template from.
mkdir -p "$TMP/Program Files/nodejs"
cp -R "$LEOHOME" "$TMP/Program Files/nodejs/leo-workflow" 2>/dev/null
SPACED="$TMP/Program Files/nodejs/leo-workflow/leo"
if [ -x "$SPACED" ]; then
  "$SPACED" --version >/dev/null 2>&1 \
    && ok "leo runs from an install path containing spaces" \
    || bad "leo cannot run from a spaced install path"
  out=$("$SPACED" task T2 2>&1 || true)
  printf '%s' "$out" | grep -q 'task created\|Done when\|is later work\|belongs to' \
    && ok "templates load from a spaced install path" \
    || bad "template loading failed from a spaced install path: $out"
else
  note "could not copy the install to a spaced path"
fi

# A temp directory with spaces: C:\Users\John Smith\AppData\Local\Temp
mkdir -p "$TMP/Temp Dir With Spaces"
out=$(TMPDIR="$TMP/Temp Dir With Spaces" "$LEO" scan 2>&1 || true)
printf '%s' "$out" | grep -qi 'wrote .leo/manifest.md\|nothing has changed' \
  && ok "leo scan works with a TMPDIR containing spaces" \
  || bad "leo scan failed with a spaced TMPDIR: $out"
rm -f .leo/manifest.md
TMPDIR="$TMP/Temp Dir With Spaces" "$LEO" check >/dev/null 2>&1 || true
leaked=$(ls "$TMP/Temp Dir With Spaces" 2>/dev/null | grep -c 'leo-' || true)
[ "${leaked:-0}" -eq 0 ] \
  && ok "no temp files leaked into a spaced TMPDIR" \
  || bad "$leaked temp file(s) left behind — Windows temp dirs are not swept"

cd "$LEOHOME"

# Static half: a variable holding a path must be quoted. Unquoted, it splits.
absent "no unquoted \$ROOT, \$LEO_HOME, \$LEO_DIR or \$TMPDIR in shipped code" \
  '(\[ +-[a-z] +\$(ROOT|LEO_HOME|LEO_DIR|LEO_SELF|PLAN|MANIFEST|TASKS)[ )]|cd \$(ROOT|LEO_HOME)|(rm|mv|cp|cat|mkdir)( -[a-zA-Z]+)* \$(ROOT|LEO_HOME|LEO_DIR|PLAN|MANIFEST)([ /]|$))' \
  $(shipped_sh)

# =========================================================================
printf '\nportability of the toolchain Git Bash actually provides\n'
# =========================================================================

# GNU-only flags. Each of these works on Linux and fails, or silently does
# something else, on Git Bash and on macOS -- so the check protects two
# platforms at once.
absent "no 'sed -i' (not portable; Git Bash and BSD sed disagree on the suffix)" \
  'sed +-i[ "'"'"']' $(shipped_sh)
absent "no 'readlink -f' (absent on macOS, unreliable on MSYS)" \
  'readlink +-f' $(shipped_sh)
absent "no 'date -d' or 'date --date' (GNU only)" \
  'date +(-d|--date)' $(shipped_sh)
absent "no 'grep -P' (PCRE is not compiled into every grep)" \
  'grep +(-[a-zA-Z]*P|--perl)' $(shipped_sh)
absent "no 'stat -c' or 'stat -f' (the two are mutually exclusive)" \
  'stat +-[cf]' $(shipped_sh)
absent "no 'sort -V', 'xargs -r' or 'cp --parents' (GNU extensions)" \
  '(sort +-[a-zA-Z]*V|xargs +-[a-zA-Z]*r|cp +--parents)' $(shipped_sh)
absent "no 'realpath' (not in Git Bash by default)" \
  '(^|[^a-z_])realpath ' $(shipped_sh)
absent "no 'sha1sum' or 'md5sum' (named differently or absent per platform)" \
  '(sha1sum|sha256sum|md5sum|shasum)' $(shipped_sh)

# Hardcoded /tmp ignores TMPDIR, and on Git Bash /tmp is a different place
# from the one Windows programs use.
absent "no hardcoded /tmp (TMPDIR must be honoured)" \
  'mktemp [^|]*"?/tmp/' $(shipped_sh)

# Hardcoded Unix absolute paths that do not exist on Windows at all.
absent "no hardcoded /usr, /bin or /etc paths" \
  '"(/usr/|/bin/|/etc/)' $(shipped_sh)

# The shebang must go through env: /bin/bash on Git Bash is not where bash is.
bad_shebang=""
for f in $(shipped_sh); do
  head -1 "$f" | grep -q '^#!' || continue
  head -1 "$f" | grep -q '^#!/usr/bin/env ' || bad_shebang="$bad_shebang ${f#"$LEOHOME"/}"
done
[ -z "$bad_shebang" ] && ok "every shebang goes through /usr/bin/env" \
                      || bad "absolute-path shebangs:$bad_shebang"

# The tools leo may use. Anything outside this list is a new dependency that
# a Windows user may not have, and leo.ps1's preflight cannot warn about a
# tool it does not know to check for.
allow='git awk sed grep tr cut sort uniq wc head tail basename dirname find mktemp readlink date cksum chmod mv rm cp cat printf ls test expr'
used=$(cat $(shipped_sh) \
       | grep -oE '(\$\(|\| *|^ *|; *|&& *)(awk|sed|grep|tr|cut|sort|uniq|wc|head|tail|basename|dirname|find|mktemp|readlink|date|cksum|chmod|stat|uname|xargs|realpath|seq|tac|rev|nl|column|timeout|nproc) ' \
       | grep -oE '[a-z]+ $' | tr -d ' ' | sort -u)
outside=""
for t in $used; do
  printf '%s\n' $allow | grep -qx "$t" || outside="$outside $t"
done
[ -z "$outside" ] && ok "leo uses only tools Git for Windows ships ($(printf '%s' "$used" | tr '\n' ' ' | wc -w | tr -d ' ') distinct)" \
                  || bad "tools outside the portable set:$outside"

# leo.ps1's preflight must actually check the tools leo uses. A preflight that
# tests for a shell and not for awk passes on a bash that cannot run leo.
if [ -f "$PS1F" ]; then
  m=""
  for t in git awk sed grep mktemp cksum; do
    grep -q "$t" "$PS1F" || m="$m $t"
  done
  [ -z "$m" ] && ok "leo.ps1's preflight covers the tools leo depends on" \
              || bad "leo.ps1 does not preflight:$m"
fi

# =========================================================================
printf '\nWindows filesystem rules a Unix tree can break\n'
# =========================================================================

# Reserved device names. A file called aux.md or con.sh cannot be created on
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

# Characters that are legal in a Unix filename and illegal in a Windows one.
illegal=$(cd "$LEOHOME" && git ls-files 2>/dev/null | grep -E '[<>:"|?*\\]' || true)
[ -z "$illegal" ] && ok "no filename uses a character Windows forbids" \
                  || bad "illegal on Windows: $illegal"

# Trailing dots and spaces are silently stripped by Windows, so two files can
# collapse into one.
trailing=$(cd "$LEOHOME" && git ls-files 2>/dev/null | grep -E '[ .]$' || true)
[ -z "$trailing" ] && ok "no filename ends in a dot or a space" \
                   || bad "Windows would rename: $trailing"

# Case-insensitive collisions. Two paths differing only in case are two files
# on Linux and one on Windows and macOS -- whichever unpacks last wins.
dupes=$(cd "$LEOHOME" && git ls-files 2>/dev/null | tr 'A-Z' 'a-z' | sort | uniq -d || true)
[ -z "$dupes" ] && ok "no two tracked paths differ only in case" \
                || bad "case-insensitive collision: $dupes"

# Path length. MAX_PATH is 260 characters including the directory the user
# installed into, and npm's global prefix is already deep.
longest=$(cd "$LEOHOME" && git ls-files 2>/dev/null | awk '{ print length($0), $0 }' | sort -rn | head -1)
len=${longest%% *}
[ "${len:-0}" -le 120 ] \
  && ok "longest tracked path is ${len} chars (leaves room under MAX_PATH)" \
  || bad "a path is ${len} chars: ${longest#* } — close to MAX_PATH once installed"

# =========================================================================
printf '\ndocumentation — a Windows user must be told what to install\n'
# =========================================================================

# Anchored on a heading, not on the word. `grep -qi windows` passed against
# the phrase "rate-limit windows" in an unrelated code sample -- a check that
# loose is worse than none, because it reports success. Same failure the
# COMMANDS-DOCUMENTED rule carries a paragraph about.
for doc in README.md GUIDE.md; do
  if grep -qE '^#+ .*[Ww]indows|^\*\*Windows' "$LEOHOME/$doc"; then
    ok "$doc has a Windows section of its own"
  else
    bad "$doc has no Windows section — a Windows user has no idea what to install"
  fi
done
grep -qi 'git for windows\|git-scm.com/download/win\|winget' "$LEOHOME/README.md" \
  && ok "README names how to get a bash on Windows" \
  || bad "README does not say where Windows users get bash"

printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
