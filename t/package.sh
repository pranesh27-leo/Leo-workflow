#!/usr/bin/env bash
# Packaging test: would `npm publish` produce a leo that actually runs?
#
# The failure this exists for is specific and silent. leo is a shell script
# that reads its own `core/` and `templates/` at runtime, and npm ships only
# what `files` in package.json lists. Drop a new directory into the source tree,
# forget the manifest entry, and every test here passes, `npm pack` succeeds,
# and the published package dies on `leo init` in somebody else's repository
# with "missing template". Nothing in the repository notices, because the
# repository has the file.
#
# So this asks the question the other way round: take what npm WOULD ship, and
# check that every file leo reads at runtime is in it.
#
# Run by t/negative.sh, which is run by `npm test`. It needs npm for the pack
# listing and degrades to the checks it can do without one rather than passing
# silently.
#
# It is deliberately NOT a `prepack` script. `npm pack` runs prepack, and this
# file runs `npm pack` -- wiring it there makes the two call each other until
# something runs out. That is not hypothetical; it is how this comment came to
# be written. `--ignore-scripts` below is the second guard on the same
# mistake, for anyone who adds a lifecycle script later.

set -u
LEOHOME=$(cd -P "$(dirname "$0")/.." && pwd)
cd "$LEOHOME"
pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

printf 'package metadata\n'

[ -f package.json ] || { printf '  FAIL  no package.json\n'; exit 1; }

# 1. One version, in two files, and they must agree. `leo --version` reads
#    VERSION; `npm install -g leo-workflow@0.5.0` reads package.json. Two
#    numbers that can disagree will, and the one that is wrong is whichever
#    the user is looking at.
pkg_ver=$(sed -n 's/^  *"version": *"\([^"]*\)".*/\1/p' package.json | head -1)
file_ver=$(tr -d ' \n' < VERSION)
if [ "$pkg_ver" = "$file_ver" ]; then
  ok "package.json version matches VERSION ($pkg_ver)"
else
  bad "package.json says $pkg_ver, VERSION says $file_ver"
fi

# 2. The bin entry has to point at something that exists and can be executed.
#    npm creates a symlink to it; a non-executable target installs cleanly and
#    fails at the first invocation with "permission denied".
bin=$(sed -n 's/.*"leo": *"\([^"]*\)".*/\1/p' package.json | head -1)
if [ -n "$bin" ] && [ -f "$bin" ]; then
  ok "bin points at $bin"
  [ -x "$bin" ] && ok "$bin is executable" || bad "$bin is not executable"
  head -1 "$bin" | grep -q '^#!' \
    && ok "$bin has a shebang" || bad "$bin has no shebang"
else
  bad "bin entry is missing or points at nothing: '$bin'"
fi

# 3. The URLs have to be the repository this actually lives in.
#
#    npm renders homepage, repository and bugs as the three links on the
#    package page, and they are the only route a stranger has back to the
#    source or to filing a bug. 0.6.0 shipped with all three pointing at
#    github.com/leo-workflow/leo, which does not exist -- invented while
#    writing the manifest and never checked against anything. A published
#    version cannot be overwritten, so the fix cost a release.
#
#    Compared against `git remote get-url origin`, not fetched: a test that
#    needs the network is a test that fails on a train, and the thing worth
#    checking here is agreement with the repository we are standing in.
remote=$(git remote get-url origin 2>/dev/null \
         | sed 's|^git+||; s|\.git$||; s|/*$||')
if [ -z "$remote" ]; then
  printf '  skip  no git remote to compare the package URLs against\n'
else
  bad_url=""
  for field in homepage repository bugs; do
    got=$(sed -n "/\"$field\"/,/[},]/p" package.json \
          | sed -n 's|.*"\(https://[^"#]*\)[^"]*".*|\1|p' \
          | sed 's|^git+||; s|\.git$||; s|/issues$||; s|/*$||' | head -1)
    [ -n "$got" ] || { bad_url="$bad_url $field:missing"; continue; }
    [ "$got" = "$remote" ] || bad_url="$bad_url $field:$got"
  done
  if [ -z "$bad_url" ]; then
    ok "homepage, repository and bugs all point at $remote"
  else
    bad "package URLs disagree with the git remote ($remote):$bad_url"
  fi
fi

# 4. leo is bash, not node. Declaring an os list is the honest way to fail on
#    Windows at install time rather than at first run.
grep -q '"os"' package.json \
  && ok "package.json declares the platforms this runs on" \
  || bad "package.json has no os field — this is a bash tool"

printf 'what npm would actually ship\n'

if ! command -v npm >/dev/null 2>&1; then
  printf '  skip  npm is not installed — the pack listing cannot be checked\n'
  printf '\n%s passed, %s failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
  exit $?
fi

# `npm pack --dry-run` prints the file list it would put in the tarball. The
# format has varied between npm majors, so the names are extracted loosely and
# matched as substrings rather than parsed.
listing=$(npm pack --dry-run --ignore-scripts --json 2>/dev/null \
          | sed -n 's/.*"path": *"\([^"]*\)".*/\1/p')
if [ -z "$listing" ]; then
  listing=$(npm pack --dry-run --ignore-scripts 2>&1 | sed 's/^npm notice *//')
fi

if [ -z "$listing" ]; then
  bad "npm pack --dry-run produced no file listing"
else
  ok "npm pack produced a listing ($(printf '%s\n' "$listing" | grep -c .) entries)"

  # Every command. This is the check that catches the real bug: a new file in
  # core/cmd/ is a new leo command with no registry entry anywhere, and the
  # only thing standing between it and a published package that does not have
  # it is this loop.
  miss=""
  for f in core/cmd/*.sh core/integrations/*.sh core/lib.sh; do
    printf '%s\n' "$listing" | grep -q "$f" || miss="$miss $f"
  done
  [ -z "$miss" ] && ok "every core file is in the package" \
                 || bad "core files npm would drop:$miss"

  # Every template. `leo init` and `leo task` cannot substitute a template
  # they cannot read, and a missing one is a repository set up wrong rather
  # than a command that fails loudly.
  miss=""
  for f in $(cd templates && find . -type f | sed 's|^\./||'); do
    printf '%s\n' "$listing" | grep -q "templates/$f" || miss="$miss $f"
  done
  [ -z "$miss" ] && ok "every template is in the package" \
                 || bad "templates npm would drop:$miss"

  # And the licence, because the vendored skills are somebody else's MIT code.
  printf '%s\n' "$listing" | grep -q 'LICENSE' \
    && ok "LICENSE is in the package" || bad "LICENSE is not in the package"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
